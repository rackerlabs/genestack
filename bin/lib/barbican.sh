#!/bin/bash
# Barbican service actions for the unified installer.
# Sourced by helpers.sh; uses its shared secret, Helm, and logging helpers.

# ── Barbican simple_crypto master KEK ───────────────────────────────────────
#
# Ported from the old install-barbican.sh. Gazpacho barbican has no built-in
# default kek: with simple_crypto enabled and no kek rendered into barbican.conf,
# barbican-api crashloops with "SimpleCrypto KEK is undefined". A kek set in an
# override file is deployed as is. Otherwise the source of truth is the
# Kubernetes Secret barbican-simple-crypto-kek, managed here:
#   kek       44-char Fernet key -> [simple_crypto_plugin] kek
#   old_keks  comma-separated history -> db-sync rewrap old_kek
#
# The chart's db-sync job rewraps every simple_crypto project KEK one-way from
# old_kek onto the rendered kek; a row it cannot unwrap fails the job, which
# barbican-api waits on (an outage, not data loss). Rotations of a
# Secret-managed kek are staged with scripts/rotate-barbican-kek.py, which this
# installer never calls.
#
# PROLOGUE
#   override_kek = conf.barbican.simple_crypto_plugin.kek from the values files,
#                  last file wins
#   secret_kek   = the kek key of barbican-simple-crypto-kek
#
# CASE 1  override_kek set          -> deploy as is: nothing is injected, no
#                                      Secret is written (NOTICE if one exists)
# CASE 2  secret_kek set            -> abort if it is not a Fernet key
#                                      -> GUARD + INJECT
# CASE 3  no Secret, deployed kek   -> adopt the kek rendered into barbican-etc
#                                      into the Secret, then INJECT
# CASE 4  no Secret, no deployed kek-> write a random kek into the Secret, then
#                                      INJECT (nothing to rewrap, no GUARD)
#
# GUARD   deployed kek = first "kek =" under [simple_crypto_plugin] in the
#         rendered barbican.conf; no kek line means the upstream default
#   no release               -> deploy
#   secret_kek == deployed   -> deploy (the rewrap is a no-op)
#   deployed in old_keks     -> deploy with a WARNING (staged rotation, one-way
#                               rewrap, back up the database first)
#   otherwise                -> abort (the rewrap could not succeed)
#
# INJECT  --set-string conf.barbican.simple_crypto_plugin.kek=<kek>
#         --set-string conf.simple_crypto_kek_rewrap.old_kek=<old_keks>
#
# Stricter than the old script in three places, all to avoid overwriting a live
# KEK when kubectl misbehaves: an API error while looking up a secret stops the
# install, a barbican-etc Secret whose barbican.conf cannot be read stops the
# install, and an existing barbican-simple-crypto-kek without a readable kek is
# never overwritten.

# The upstream default kek that every pre-Gazpacho deploy without an explicit
# kek ran on. Public knowledge (OpenStack docs, OSH chart values); derived at
# runtime so no key-shaped blob sits in the repo.
barbican_kek_well_known() {
    printf '%s' 'thirty_two_byte_keyblahblahblahh' | base64 | tr -d '\n'
}

# 44 chars that base64-decode to exactly 32 bytes: a Fernet key.
barbican_kek_format_ok() {
    [[ ${#1} -eq 44 ]] &&
        (( $(printf '%s' "$1" | tr -- '-_' '+/' | base64 "${BASE64_FLAG:--d}" 2>/dev/null | wc -c) == 32 ))
}

barbican_kek_warn_default() {
    local source="$1"
    cat >&2 <<EOF
################################################################################
#                                                                              #
#  WARNING: BARBICAN IS USING THE WELL-KNOWN DEFAULT SIMPLE_CRYPTO KEK          #
#                                                                              #
#  Source: ${source}
#                                                                              #
#  This key is public chart/default material. Any secret encrypted with          #
#  simple_crypto under this KEK should be treated as protected by a default      #
#  password. Plan a Barbican KEK rotation with a database backup and use:        #
#                                                                              #
#    ${GENESTACK_BASE_DIR}/scripts/rotate-barbican-kek.py --stage               #
#                                                                              #
#  Do not delete or randomly replace the KEK on a brownfield cluster; that can   #
#  strand existing Barbican project keys.                                       #
#                                                                              #
################################################################################
EOF
}

# The kek the running release renders into barbican.conf: the first "kek ="
# line under [simple_crypto_plugin] in the barbican-etc Secret (the rule the
# rotation tool applies too, so a kek option in another section is never
# mistaken for it). Prints nothing when there is no release. A release with no
# kek line is a pre-Gazpacho deploy on the implicit upstream default, so that
# default is what it prints then. Returns 1, printing nothing, when the answer
# cannot be determined.
barbican_kek_deployed() {
    local ns="$1" state conf section line
    state="$(secret_state "$ns" barbican-etc)"
    case "$state" in
        present) ;;
        absent) return 0 ;;
        *)
            log_error "Cannot tell whether ${ns}/barbican-etc exists: ${state#error: }"
            return 1
            ;;
    esac
    conf="$(secret_get "$ns" barbican-etc barbican.conf)"
    if [[ -z "$conf" ]]; then
        log_error "${ns}/barbican-etc exists but its barbican.conf could not be read;"
        log_error "  cannot tell which simple_crypto kek is deployed, so no kek will be generated or changed."
        return 1
    fi
    # the [simple_crypto_plugin] section only: from its header up to the next header
    section="$(sed -n '/^\[simple_crypto_plugin\]/,/^\[/p' <<< "$conf")"
    # the first kek line; when there are several, the first one encrypts
    line="$(grep -m1 -E '^[[:space:]]*kek[[:space:]]*=' <<< "$section" || true)"
    line="${line#*=}"                                  # drop "kek =", keeping the key's own trailing =
    line="$(sed "s/[[:space:]\"']//g" <<< "$line")"    # strip quotes and whitespace
    if [[ -z "$line" ]]; then
        barbican_kek_well_known
        return 0
    fi
    printf '%s' "$line"
}

# Writes the Secret over stdin so the kek never appears in argv or ps.
barbican_kek_write_secret() {
    local ns="$1" secret="$2" kek="$3" old_keks="${4:-}"
    $KUBECTL_BIN --namespace "$ns" apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${secret}
  namespace: ${ns}
type: Opaque
data:
  kek: "$(printf '%s' "$kek" | base64 | tr -d '\n')"
  old_keks: "$(printf '%s' "$old_keks" | base64 | tr -d '\n')"
EOF
}

# Usage: ensure_barbican_simple_crypto_kek <merged service YAML> <namespace>
# Appends the kek (and old_kek) Helm arguments to helm_set_args. Returns 1 when
# the install must stop.
ensure_barbican_simple_crypto_kek() {
    local svc_yaml_content="$1" ns="$2"
    local kek_secret="barbican-simple-crypto-kek"
    local well_known state f v token
    local override_kek="" secret_kek="" secret_old="" deployed_kek="" new_kek="" deployed_rc

    well_known="$(barbican_kek_well_known)"

    # kek set in a values file: the last file wins (Helm precedence). Only its
    # presence matters here; the -f files deliver the value to Helm as is.
    while IFS= read -r token; do
        [[ -z "$token" || "$token" == "-f" ]] && continue
        f="$token"
        v="$(yq e '.conf.barbican.simple_crypto_plugin.kek // ""' "$f" 2>/dev/null | head -n1)"
        [[ -n "$v" && "$v" != "null" ]] && override_kek="$v"
    done < <(build_helm_args "$svc_yaml_content" 2>/dev/null)

    state="$(secret_state "$ns" "$kek_secret")"
    case "$state" in
        present)
            secret_kek="$(secret_get "$ns" "$kek_secret" kek)"
            secret_old="$(secret_get "$ns" "$kek_secret" old_keks)"
            ;;
        absent) ;;
        *)
            log_error "Cannot tell whether ${ns}/${kek_secret} exists: ${state#error: }"
            log_error "  Not touching the Barbican kek."
            return 1
            ;;
    esac

    if [[ -n "$override_kek" ]]; then
        # Case 1: the values files carry the kek (and any old_kek).
        echo "conf.barbican.simple_crypto_plugin.kek is set in the override files: deploying it as is."
        if [[ "$override_kek" == "$well_known" ]]; then
            barbican_kek_warn_default "override files: conf.barbican.simple_crypto_plugin.kek"
        fi
        if [[ -n "$secret_kek" ]]; then
            echo "NOTICE: ${kek_secret} exists but is ignored while the override files set the kek."
        fi
        return 0
    fi

    if [[ "$state" == "present" && -z "$secret_kek" ]]; then
        log_error "${ns}/${kek_secret} exists but holds no readable kek; refusing to overwrite it."
        log_error "  Fix the Secret, or adopt the deployed kek with ${GENESTACK_BASE_DIR}/scripts/rotate-barbican-kek.py --adopt."
        return 1
    fi

    if [[ -n "$secret_kek" ]]; then
        # Case 2: the Secret is the kek. Guard the db-sync rewrap before injecting it.
        if ! barbican_kek_format_ok "$secret_kek"; then
            echo "ERROR: ${kek_secret} holds a value that is not a 44-char Fernet key; refusing to deploy" >&2
            return 1
        fi
        if [[ "$secret_kek" == "$well_known" ]]; then
            barbican_kek_warn_default "${ns}/${kek_secret}:kek"
        fi
        deployed_kek="$(barbican_kek_deployed "$ns")" && deployed_rc=0 || deployed_rc=$?
        [[ "$deployed_rc" -eq 0 ]] || return 1
        if [[ -z "$deployed_kek" ]]; then
            echo "no barbican release yet: injecting the kek from ${kek_secret}."
        elif [[ "$secret_kek" == "$deployed_kek" ]]; then
            echo "Secret kek matches the deployed kek; the db-sync rewrap is a no-op."
        elif [[ ",${secret_old}," == *",${deployed_kek},"* ]]; then
            # A staged rotation. rotate-barbican-kek.py --stage records the deployed
            # kek in old_keks, and old_keks is exactly what is injected below, so the
            # rewrap's decryptor set never depends on a chart default.
            echo "WARNING: Secret kek differs from the deployed kek: this deploy performs a ONE-WAY rewrap of"
            echo "         every simple_crypto project KEK during db-sync. Back up the barbican DB first."
            echo "         Afterwards run: ${GENESTACK_BASE_DIR}/scripts/rotate-barbican-kek.py --validate deployed"
            echo "         and confirm the db-sync job logs show zero rewrap failures."
        else
            echo "ERROR: Secret kek differs from the deployed kek, and the deployed kek is not in" >&2
            echo "       ${kek_secret}/old_keks, so the db-sync rewrap could not unwrap the existing project" >&2
            echo "       keys and barbican would not start. Not deploying. Stage rotations only with" >&2
            echo "       ${GENESTACK_BASE_DIR}/scripts/rotate-barbican-kek.py --stage (it records the deployed" >&2
            echo "       kek in old_keks), or delete the Secret deliberately and re-adopt the deployed kek with" >&2
            echo "       ${GENESTACK_BASE_DIR}/scripts/rotate-barbican-kek.py --adopt before re-running this install." >&2
            return 1
        fi
    else
        # No Secret and no override: first preserve any kek already rendered into
        # the deployed barbican-etc secret. Only a deployment with no recoverable
        # deployed kek can fall through to fresh generation.
        deployed_kek="$(barbican_kek_deployed "$ns")" && deployed_rc=0 || deployed_rc=$?
        [[ "$deployed_rc" -eq 0 ]] || return 1
        if [[ -n "$deployed_kek" ]]; then
            if ! barbican_kek_format_ok "$deployed_kek"; then
                echo "ERROR: ${kek_secret} is absent and barbican-etc contains an invalid simple_crypto kek;" >&2
                echo "       refusing to replace it with a random value. Fix or adopt the deployed kek manually." >&2
                return 1
            fi
            if [[ "$deployed_kek" == "$well_known" ]]; then
                barbican_kek_warn_default "${ns}/barbican-etc:barbican.conf"
            fi
            echo "${kek_secret} is absent; adopting the deployed simple_crypto kek from barbican-etc."
            barbican_kek_write_secret "$ns" "$kek_secret" "$deployed_kek" ""
            secret_kek="$(secret_get "$ns" "$kek_secret" kek)"
            secret_old=""
            if [[ "$secret_kek" != "$deployed_kek" ]]; then
                echo "ERROR: ${kek_secret} did not persist the deployed kek read from barbican-etc" >&2
                return 1
            fi
        else
            # No Secret, no override, and no deployed barbican-etc kek. The installer
            # has no existing KEK source to preserve, so create the initial managed KEK.
            echo "${kek_secret} is absent and no deployed simple_crypto kek was found: generating a fresh kek."
            # 32 random bytes, urlsafe base64: the Fernet key format.
            new_kek="$(head -c 32 /dev/urandom | base64 | tr -d '\n' | tr '+/' '-_')"
            barbican_kek_write_secret "$ns" "$kek_secret" "$new_kek" ""
            unset new_kek
            # Read it back: only a kek that is actually stored gets injected.
            secret_kek="$(secret_get "$ns" "$kek_secret" kek)"
            secret_old=""
            if ! barbican_kek_format_ok "$secret_kek"; then
                echo "ERROR: ${kek_secret} still holds no valid kek after generating one" >&2
                return 1
            fi
            echo "fresh kek: the db-sync rewrap has no project keys to process."
        fi
    fi

    # Inject (cases 2, 3 and 4).
    append_helm_set_string_arg "conf.barbican.simple_crypto_plugin.kek" "$secret_kek"
    if [[ -n "$secret_old" ]]; then
        # a comma is --set list syntax; escape it so the whole history survives as one string
        append_helm_set_string_arg "conf.simple_crypto_kek_rewrap.old_kek" "${secret_old//,/\\,}"
    fi
    return 0
}

# ── Barbican SoftHSM2 (PKCS#11) ─────────────────────────────────────────────
#
# Ported from the old install-barbican.sh.
#   - SoftHSM p11 counts as enabled when any values file (base, global or site)
#     contains both p11_crypto and libsofthsm2, or when BARBICAN_HSM_ENABLED or
#     HYPERCONVERGED_BARBICAN_HSM is true. The base values enable it, so it is on
#     unless a deployment replaces them.
#   - With the lab flags and no site values file, the SoftHSM overlay is
#     generated by writeServiceHelmOverrides (scripts/lib/hyperconverged-common.sh).
#     An existing site file is never rewritten.
#   - With p11 enabled, the PIN secret barbican-hsm-credentials is created once
#     and an existing PIN is never changed. The token is initialized with it.
#   - Whenever the PIN secret holds a pin, it is injected as
#     conf.barbican.p11_crypto_plugin.login (--set, as before).
#   - After Helm, initBarbicanHSMKeys creates the token, MKEK and HMAC key. It is
#     idempotent.
# Stricter than the old script in one place: an API error while looking up the
# PIN secret stops the install, because acting on a guess could replace the PIN
# that protects the existing token.

# 0 when SoftHSM p11 is configured in any of the service's values files.
barbican_softhsm_in_values() {
    local svc_yaml_content="$1" token
    while IFS= read -r token; do
        [[ -z "$token" || "$token" == "-f" ]] && continue
        if [[ -f "$token" ]] && grep -q "p11_crypto" "$token" 2>/dev/null && grep -q "libsofthsm2" "$token" 2>/dev/null; then
            return 0
        fi
    done < <(build_helm_args "$svc_yaml_content" 2>/dev/null)
    return 1
}

# Usage: ensure_barbican_hsm_setup <merged service YAML> <namespace> <service name>
# Appends the PIN Helm argument to helm_set_args and exports
# GENESTACK_BARBICAN_SOFTHSM_P11 for the post-install key initialization.
ensure_barbican_hsm_setup() {
    local svc_yaml_content="$1" ns="$2" service_name="$3"
    local pin_secret="barbican-hsm-credentials"
    local softhsm=false site_file common state existing_pin="" hsm_pin=""

    site_file="${GENESTACK_OVERRIDES_DIR}/helm-configs/${service_name}/barbican-helm-overrides.yaml"

    if [[ "${BARBICAN_HSM_ENABLED:-false}" == "true" || "${HYPERCONVERGED_BARBICAN_HSM:-false}" == "true" ]]; then
        softhsm=true
        # Generate a SoftHSM overlay only when no site file exists. Never rewrite
        # an existing environment override (region, images, policy would be lost).
        if [[ ! -f "$site_file" ]]; then
            echo "HSM enabled and ${site_file} is missing. Generating SoftHSM overlay..."
            common="${GENESTACK_BASE_DIR}/scripts/lib/hyperconverged-common.sh"
            if [[ ! -f "$common" ]]; then
                log_error "Cannot generate the SoftHSM overlay: ${common} not found."
                return 1
            fi
            if ! (
                # shellcheck source=/dev/null
                source "$common" >/dev/null 2>&1
                writeServiceHelmOverrides "${GENESTACK_OVERRIDES_DIR}/helm-configs"
            ); then
                log_error "Failed to generate the SoftHSM overlay ${site_file}."
                return 1
            fi
        fi
    fi

    if [[ "$softhsm" != "true" ]] && barbican_softhsm_in_values "$svc_yaml_content"; then
        softhsm=true
    fi

    state="$(secret_state "$ns" "$pin_secret")"
    case "$state" in
        present) existing_pin="$(secret_get "$ns" "$pin_secret" pin)" ;;
        absent) ;;
        *)
            log_error "Cannot tell whether ${ns}/${pin_secret} exists: ${state#error: }"
            log_error "  Not touching the SoftHSM PIN."
            return 1
            ;;
    esac

    # Ensure barbican-hsm-credentials exists. The install path creates this secret
    # once and leaves it alone on later upgrades.
    if [[ "$softhsm" == "true" ]]; then
        if [[ -n "$existing_pin" ]]; then
            echo "barbican-hsm-credentials already present — leaving PIN unchanged"
        else
            echo "Creating barbican-hsm-credentials (missing on this brownfield cluster)"
            hsm_pin="$(secret_generate 32)"
            secret_ensure "$ns" "$pin_secret" pin "$hsm_pin" || return 1
            hsm_pin=""
        fi
    fi

    # PKCS#11 SoftHSM2 PIN injection
    hsm_pin="$(secret_get "$ns" "$pin_secret" pin)"
    if [[ -n "$hsm_pin" ]]; then
        echo "HSM credentials found - injecting p11_crypto_plugin.login"
        append_helm_set_arg "conf.barbican.p11_crypto_plugin.login" "$hsm_pin"
    fi
    hsm_pin=""

    GENESTACK_BARBICAN_SOFTHSM_P11="$softhsm"
    export GENESTACK_BARBICAN_SOFTHSM_P11
    return 0
}

# Post-install SoftHSM2 key initialization (token, MKEK, HMAC). Runs when the
# setup above found p11 enabled. --dry-run skips it: nothing was deployed.
run_barbican_hsm_init() {
    local common="${GENESTACK_BASE_DIR}/scripts/lib/hyperconverged-common.sh" arg

    if [[ "${GENESTACK_BARBICAN_SOFTHSM_P11:-false}" != "true" ]]; then
        log_info "SoftHSM p11 is not enabled; skipping SoftHSM key initialization."
        return 0
    fi
    if declare -p CL_EXTRA_HELM_ARGS >/dev/null 2>&1; then
        for arg in "${CL_EXTRA_HELM_ARGS[@]:-}"; do
            if [[ "$arg" == "--dry-run" || "$arg" == --dry-run=* ]]; then
                log_info "--dry-run is set; skipping SoftHSM key initialization."
                return 0
            fi
        done
    fi
    if [[ ! -f "$common" ]]; then
        echo "ERROR: initBarbicanHSMKeys not found; SoftHSM keys were not initialized"
        return 1
    fi
    (
        # shellcheck source=/dev/null
        source "$common" >/dev/null 2>&1 || true
        if ! declare -f initBarbicanHSMKeys >/dev/null 2>&1; then
            echo "ERROR: initBarbicanHSMKeys not found; SoftHSM keys were not initialized"
            exit 1
        fi
        initBarbicanHSMKeys
    )
}
