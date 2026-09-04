#!/bin/bash
# Barbican simple_crypto KEK resolution for bin/install-barbican.sh.
#
# Sourced by install-barbican.sh. Entry point:
#
#   barbican_kek_resolve <override.yaml>...
#
# Appends --set/--set-string helm arguments to the caller's `set_args` array
# and returns 0, or prints guidance and exits 1 when deploying would leave
# Barbican unable to start. Expects SERVICE_NAMESPACE and SERVICE_NAME_DEFAULT
# from the caller (defaults: openstack / barbican). Requires kubectl, helm, yq
# on the deploy host; nothing else (DB validation runs inside barbican-api).
#
# May also be executed directly for one maintenance action:
#
#   scripts/barbican/kek.sh record
#
# which (re)writes the Secret's document in /etc/genestack/kubesecrets.yaml
# from the cluster (escalating with non-interactive sudo when the file is
# root-owned) - for re-syncing the file outside of a deploy.
#
# Background
# ----------
# Gazpacho barbican has NO built-in default kek: if simple_crypto is enabled
# and nothing renders a kek into barbican.conf, barbican-api crashloops with
# 'SimpleCrypto KEK is undefined'. The kek's source of truth is the
# barbican-simple-crypto-plugin-kek Secret, injected via --set (highest helm
# precedence). This library writes key material in two situations only: a
# fresh kek when no simple_crypto data exists yet, and adoption of the kek a
# running Barbican already uses (DB-validated, never a new key). Rotations
# are staged exclusively with the sibling barbican-kek-rewrite-planner.py.
#
# The chart's db-sync job runs a ONE-WAY rewrap of every simple_crypto project
# KEK whenever both conf.barbican.simple_crypto_plugin.kek and
# conf.simple_crypto_kek_rewrap.old_kek are set (old_kek defaults to the
# upstream well-known key). Rows already wrapped with the target kek are
# skipped; rows none of the old keks can unwrap FAIL the job and API pods wait
# on it. No row is modified on failure: a bad rewrap is an outage, not data
# loss. This library still refuses to arm a rewrap it can prove cannot succeed.
#
# Cases
# -----
#  1. Greenfield: Secret created by create-secrets.sh          -> inject.
#  2. Brownfield, barbican data present, no Secret, no override kek
#     -> adopt the deployed kek (validated, no rotation), then inject.
#  3. Brownfield cluster, barbican never (successfully) deployed: no Secret,
#     no override kek, no simple_crypto rows in kek_data     -> generate, inject.
#  4. simple_crypto not in the effective enabled_crypto_plugins (HSM-only)
#     -> no kek required. Mixed p11_crypto + simple_crypto == cases 1-3.
#  *  kek supplied only by an override file                  -> honored.
#  *  Secret kek != deployed kek (staged rotation)           -> allowed only
#     when old_keks/well-known covers the deployed kek; otherwise refused.
#
# After resolution the Secret's document in /etc/genestack/kubesecrets.yaml
# (when that file exists) is appended or rewritten to match the cluster, so
# the file create-secrets.sh produced stays the record of truth.
#
# Knobs (default true; "false" turns the path into a hard error with guidance):
#   BARBICAN_KEK_AUTO_ADOPT      case 2
#   BARBICAN_KEK_AUTO_GENERATE   case 3
#   BARBICAN_KEK_KUBESECRETS     path of the secrets file to keep in sync

BARBICAN_KEK_SECRET="barbican-simple-crypto-plugin-kek"
BARBICAN_KEK_DATA_KEY="barbican_simple_crypto_plugin_kek"
BARBICAN_KEK_OLD_DATA_KEY="old_keks"
BARBICAN_KEK_PLANNER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/barbican-kek-rewrite-planner.py"
BARBICAN_KEK_AUTO_ADOPT="${BARBICAN_KEK_AUTO_ADOPT:-true}"
BARBICAN_KEK_AUTO_GENERATE="${BARBICAN_KEK_AUTO_GENERATE:-true}"
# create-secrets.sh output, re-applied by setup-infrastructure.sh. Kept in
# sync with the cluster Secret so a later re-apply cannot revert the kek.
BARBICAN_KEK_KUBESECRETS="${BARBICAN_KEK_KUBESECRETS:-${GENESTACK_OVERRIDES_DIR:-/etc/genestack}/kubesecrets.yaml}"
# Upstream barbican default kek (public knowledge; printed in the OpenStack
# docs and the OSH chart values). Derived at runtime so no key-shaped blob
# sits in the repo. NOT a secret and NOT one of our keys.
BARBICAN_WELL_KNOWN_KEK="$(printf '%s' 'thirty_two_byte_keyblahblahblahh' | base64 | tr -d '\n')"

kek_log() { echo "[barbican-kek] $*" >&2; }
kek_die() { kek_log "ERROR: $*"; exit 1; }
kek_ns()  { printf '%s' "${SERVICE_NAMESPACE:-openstack}"; }

# 44 chars that base64(url)-decode to exactly 32 bytes.
kek_format_ok() {
    local k="$1"
    [[ ${#k} -eq 44 ]] || return 1
    (( $(printf '%s' "$k" | tr -- '-_' '+/' | base64 -d 2>/dev/null | wc -c) == 32 ))
}

# Same construction as generate_fernet_token in create-secrets.sh.
kek_generate() {
    LC_ALL=C tr -dc '_A-Za-z0-9' < /dev/urandom | head -c 32 | base64 | tr -d '\n'
}

# Decoded value of one data key of a Secret, or '' if secret/key is missing.
kek_secret_field() {
    kubectl --namespace "$(kek_ns)" get secret "$1" -o "jsonpath={.data.$2}" 2>/dev/null \
        | base64 -d 2>/dev/null || true
}

# First 'kek =' under [simple_crypto_plugin] in the rendered barbican.conf of
# the CURRENT release (barbican-etc). Empty when no release, or when the last
# render carried no explicit kek (pre-Gazpacho: implicit well-known default).
kek_deployed() {
    kek_secret_field barbican-etc 'barbican\.conf' | awk '
        /^[[:space:]]*\[/ { insec = ($0 ~ /^[[:space:]]*\[simple_crypto_plugin\]/); next }
        insec && /^[[:space:]]*kek[[:space:]]*=/ {
            sub(/^[^=]*=[[:space:]]*/, ""); gsub(/["'"'"']/, ""); print; exit }'
}

# conf.barbican.simple_crypto_plugin.kek across the override files; the last
# file wins (helm precedence). A list value yields its first entry.
kek_from_overrides() {
    local f v found=""
    for f in "$@"; do
        v="$(yq eval '.conf.barbican.simple_crypto_plugin.kek // "" | (select(type == "!!seq") | .[0]) // .' "$f" 2>/dev/null | head -n1)"
        [[ -n "$v" && "$v" != "null" ]] && found="$v"
    done
    printf '%s' "$found"
}

# Is simple_crypto in the effective crypto plugin set? Helm replaces lists
# wholesale, so the last override defining enabled_crypto_plugins wins; with
# none defined barbican's own default is [simple_crypto]. Also honours
# crypto_plugin: simple_crypto under multi-backend secretstore blocks.
kek_simple_crypto_enabled() {
    local f v plugins="" multi=""
    for f in "$@"; do
        v="$(yq eval '(.conf.barbican.crypto.enabled_crypto_plugins // []) | .[]' "$f" 2>/dev/null)"
        [[ -n "$v" ]] && plugins="$v"
        v="$(yq eval '.conf.barbican | to_entries | .[] | .value | select(type == "!!map") | .crypto_plugin // ""' "$f" 2>/dev/null)"
        [[ -n "$v" ]] && multi+="$v"$'\n'
    done
    [[ -z "$plugins" ]] && return 0
    grep -qx 'simple_crypto' <<< "$plugins" && return 0
    grep -qx 'simple_crypto' <<< "$multi"
}

kek_release_exists() {
    helm status "${SERVICE_NAME_DEFAULT:-barbican}" --namespace "$(kek_ns)" >/dev/null 2>&1
}

# State of simple_crypto rows in barbican.kek_data, read on the MariaDB
# primary with the root credential the deploy already uses. SELECT only; the
# password travels over stdin, never argv. Prints: rows | empty | nodb | unknown
kek_db_state() {
    local pod pw probe out
    pod="$(kubectl --namespace "$(kek_ns)" get mariadb mariadb-cluster \
        -o jsonpath='{.status.currentPrimary}' 2>/dev/null)"
    pod="${pod:-mariadb-cluster-0}"
    pw="$(kek_secret_field mariadb root-password)"
    if [[ -z "$pw" ]]; then echo unknown; return; fi
    read -r -d '' probe <<'EOF' || true
IFS= read -r MYSQL_PWD; export MYSQL_PWD
t=$(mariadb -uroot -N -B -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='barbican' AND table_name='kek_data'") || exit 1
[ "$t" = "0" ] && { echo nodb; exit 0; }
n=$(mariadb -uroot -N -B -e "SELECT COUNT(*) FROM barbican.kek_data WHERE plugin_name LIKE '%simple_crypto%'") || exit 1
[ "$n" = "0" ] && echo empty || echo rows
EOF
    out="$(kubectl --namespace "$(kek_ns)" exec -i "$pod" -- sh -c "$probe" <<< "$pw" 2>/dev/null)"
    case "$out" in
        rows|empty|nodb) echo "$out" ;;
        *) echo unknown ;;
    esac
}

# Create/update the Secret via stdin (kek never hits argv/ps); verify readback.
kek_write_secret() {
    local kek="$1" old="$2"
    kek_secret_doc "$kek" "$old" | kubectl --namespace "$(kek_ns)" apply -f - >/dev/null \
        || kek_die "failed to write Secret ${BARBICAN_KEK_SECRET}"
    [[ "$(kek_secret_field "$BARBICAN_KEK_SECRET" "$BARBICAN_KEK_DATA_KEY")" == "$kek" ]] \
        || kek_die "post-write readback mismatch on ${BARBICAN_KEK_SECRET}"
}

# The Secret rendered as a YAML document (same shape as create-secrets.sh).
kek_secret_doc() {
    local kek="$1" old="$2"
    cat <<EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: ${BARBICAN_KEK_SECRET}
  namespace: $(kek_ns)
type: Opaque
data:
  ${BARBICAN_KEK_DATA_KEY}: "$(printf '%s' "$kek" | base64 | tr -d '\n')"
  ${BARBICAN_KEK_OLD_DATA_KEY}: "$(printf '%s' "$old" | base64 | tr -d '\n')"
EOF
}

# Bring the Secret's document in kubesecrets.yaml in line with the cluster:
# append it when missing, rewrite it in place when the values differ. The
# file's other documents are passed through byte-for-byte; inode, owner and
# mode are preserved. No-op when the file does not exist.
kek_record_kubesecrets() {
    local file="$BARBICAN_KEK_KUBESECRETS" kek old content file_kek file_old updated
    local -a priv=()
    [[ -f "$file" ]] || return 0
    kek="$(kek_secret_field "$BARBICAN_KEK_SECRET" "$BARBICAN_KEK_DATA_KEY")"
    old="$(kek_secret_field "$BARBICAN_KEK_SECRET" "$BARBICAN_KEK_OLD_DATA_KEY")"
    [[ -n "$kek" ]] || return 0

    # create-secrets.sh leaves the file 0640 root-owned and the automated flow
    # runs under sudo. A manual run as an unprivileged user escalates with
    # non-interactive sudo (never prompts, so a deploy cannot hang here).
    if [[ ! -r "$file" || ! -w "$file" ]]; then
        if sudo -n true 2>/dev/null; then
            priv=(sudo -n)
        else
            kek_log "WARNING: ${file} is not writable by $(id -un) and passwordless sudo is unavailable;"
            kek_log "         the kek was NOT recorded there. The cluster Secret is authoritative. To record it:"
            kek_log "           sudo ${BASH_SOURCE[0]} record"
            return 0
        fi
    fi
    # All file I/O goes through cat/tee so the same path works with or without
    # sudo; tee writes in place, preserving inode, owner and mode.
    content="$("${priv[@]}" cat "$file" 2>/dev/null)" \
        || { kek_log "WARNING: could not read ${file}; kek not recorded"; return 0; }

    if ! grep -Eq "^[[:space:]]+name:[[:space:]]*${BARBICAN_KEK_SECRET}[[:space:]]*$" <<< "$content"; then
        kek_secret_doc "$kek" "$old" | "${priv[@]}" tee -a "$file" >/dev/null 2>&1 \
            || { kek_log "WARNING: could not append ${BARBICAN_KEK_SECRET} to ${file}"; return 0; }
        kek_log "recorded ${BARBICAN_KEK_SECRET} in ${file} (appended${priv:+, via sudo})"
        return 0
    fi

    file_kek="$(yq eval "select(.metadata.name == \"${BARBICAN_KEK_SECRET}\") | .data.${BARBICAN_KEK_DATA_KEY} // \"\"" - <<< "$content" 2>/dev/null | head -n1 | base64 -d 2>/dev/null)"
    file_old="$(yq eval "select(.metadata.name == \"${BARBICAN_KEK_SECRET}\") | .data.${BARBICAN_KEK_OLD_DATA_KEY} // \"\"" - <<< "$content" 2>/dev/null | head -n1 | base64 -d 2>/dev/null)"
    [[ "$file_kek" == "$kek" && "$file_old" == "$old" ]] && return 0

    # Replace only the matching document. Documents are delimited by '---'
    # lines; the one whose metadata.name matches is swapped for the fresh
    # rendering, everything else is emitted unchanged. The replacement is
    # passed through the environment: awk -v cannot carry newlines portably.
    if updated="$(KEK_DOC="$(kek_secret_doc "$kek" "$old")" awk -v name="$BARBICAN_KEK_SECRET" '
        function flush() {
            if (buf == "") return
            if (buf ~ ("\n[[:space:]]+name:[[:space:]]*" name "[[:space:]]*\n")) { printf "%s\n", ENVIRON["KEK_DOC"]; replaced = 1 }
            else printf "%s", buf
            buf = ""
        }
        /^---[[:space:]]*$/ { flush(); buf = $0 "\n"; next }
        { buf = buf $0 "\n" }
        END { flush(); exit(replaced ? 0 : 1) }' <<< "$content")" \
       && printf '%s\n' "$updated" | "${priv[@]}" tee "$file" >/dev/null 2>&1; then
        kek_log "recorded ${BARBICAN_KEK_SECRET} in ${file} (updated to match the cluster${priv:+, via sudo})"
    else
        kek_log "WARNING: ${BARBICAN_KEK_SECRET} document in ${file} not rewritten; update it manually"
    fi
}

# Does the candidate kek unwrap the active simple_crypto project KEKs in
# barbican.kek_data? Runs inside the barbican-api container, which has the
# DB credentials and the cryptography/sqlalchemy libraries; nothing is
# needed on the deploy host beyond kubectl. SELECT only. The candidate is
# format-gated (base64 alphabet only) before being substituted into the
# script text, so it is never visible in argv. Mirrors the planner's
# --validate. Returns 0 all rows unwrap / 1 not / 2 bad candidate.
kek_validate_against_db() {
    local cand="$1"
    kek_format_ok "$cand" || return 2
    kubectl --namespace "$(kek_ns)" exec -i deploy/barbican-api -c barbican-api -- \
        python3 -W ignore::SyntaxWarning - <<EOF
import sys
from cryptography.fernet import Fernet
from oslo_config import cfg
import sqlalchemy as sa

conf = cfg.ConfigOpts()
conf.register_opts([cfg.StrOpt('connection', secret=True)], group='database')
conf(args=[], project='barbican')
with sa.create_engine(conf.database.connection).connect() as c:
    rows = c.execute(sa.text(
        "SELECT plugin_meta FROM kek_data WHERE active = 1 "
        "AND plugin_meta IS NOT NULL AND plugin_name LIKE '%simple_crypto%' "
        "LIMIT 25")).fetchall()
if not rows:
    print("no active simple_crypto project KEKs in DB; nothing to unwrap", file=sys.stderr)
    sys.exit(0)
f = Fernet("${cand}")
ok = 0
for (m,) in rows:
    try:
        f.decrypt(m.encode() if isinstance(m, str) else m)
        ok += 1
    except Exception:
        pass
print("unwrapped " + str(ok) + "/" + str(len(rows)) + " sampled project KEKs", file=sys.stderr)
sys.exit(0 if ok == len(rows) else 1)
EOF
}

# Case 2: adopt the kek the running Barbican already uses into the Secret.
# Bash equivalent of the planner's --adopt: resolve the deployed kek (explicit
# line in the rendered barbican.conf, else the pre-Gazpacho implicit upstream
# default), prove it unwraps the DB project keys, record every previously
# configured kek in old_keks, write the Secret. No new key: the next db-sync
# rewrap is a no-op. Only called while the Secret is absent, so the planner's
# staged-rotation no-clobber check does not apply here.
#
# Returns 0 adopted / 2 no ready barbican-api pod / 3 deployed kek does not
# unwrap the DB rows / 1 anything else.
kek_adopt() {
    local active old k ready
    active="$(kek_deployed)"
    active="${active:-$BARBICAN_WELL_KNOWN_KEK}"
    kek_format_ok "$active" || { kek_log "deployed kek is not a valid 44-char Fernet key"; return 1; }
    ready="$(kubectl --namespace "$(kek_ns)" get deploy/barbican-api \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null)"
    [[ "${ready:-0}" -gt 0 ]] 2>/dev/null || return 2
    kek_log "adopting the deployed kek (no rotation); validating it against barbican.kek_data inside barbican-api"
    kek_validate_against_db "$active"
    case $? in
        0) ;;
        1) return 3 ;;
        *) return 1 ;;
    esac
    # History for the rewrap decryptor: deployed kek, every old kek the chart
    # rendered ('old_kek' <=2024.x, 'old_keks' Epoxy+), upstream default.
    old=""
    while IFS= read -r k; do
        kek_format_ok "$k" || continue
        grep -qxF -- "$k" <<< "$old" || old+="$k"$'\n'
    done < <(printf '%s\n' "$active" \
        "$(kek_secret_field barbican-etc old_keks)" \
        "$(kek_secret_field barbican-etc old_kek)" \
        "$BARBICAN_WELL_KNOWN_KEK" | tr ',' '\n')
    old="$(paste -sd, - <<< "${old%$'\n'}")"
    kek_write_secret "$active" "$old"
    kek_log "adopted: ${BARBICAN_KEK_SECRET} now holds the deployed kek and $(tr ',' '\n' <<< "$old" | wc -l | tr -d ' ') old kek(s)."
    kek_log "         Any kek line in your override files can be removed after one successful deploy."
}

barbican_kek_resolve() {
    local -a files=("$@")
    local secret_kek secret_old override_kek deployed db_state
    local etc_exists=false release=false simple_crypto=true generated=false

    secret_kek="$(kek_secret_field "$BARBICAN_KEK_SECRET" "$BARBICAN_KEK_DATA_KEY")"
    if [[ -n "$secret_kek" ]] && ! kek_format_ok "$secret_kek"; then
        kek_die "${BARBICAN_KEK_SECRET} exists but is not a valid 44-char Fernet key; refusing to deploy"
    fi
    override_kek="$(kek_from_overrides "${files[@]}")"
    if [[ -n "$override_kek" ]] && ! kek_format_ok "$override_kek"; then
        kek_die "conf.barbican.simple_crypto_plugin.kek in the override files is not a valid 44-char Fernet key"
    fi
    kek_release_exists && release=true
    kubectl --namespace "$(kek_ns)" get secret barbican-etc >/dev/null 2>&1 && etc_exists=true
    deployed="$(kek_deployed)"
    kek_simple_crypto_enabled "${files[@]}" || simple_crypto=false

    if [[ -z "$secret_kek" ]]; then
        if [[ "$simple_crypto" == "false" ]]; then
            # Case 4: HSM/other backend only; no kek needed for startup.
            kek_log "simple_crypto is not in enabled_crypto_plugins; no kek required (Secret absent)."
            if [[ "$(kek_db_state)" == "rows" ]]; then
                kek_log "WARNING: barbican.kek_data still holds simple_crypto-wrapped project keys;"
                kek_log "         those secrets are unreadable while simple_crypto is disabled."
            fi
            return 0
        fi
        if [[ -n "$override_kek" ]]; then
            kek_log "NOTICE: kek supplied by an override file (Secret absent). Deploying as-is."
            kek_log "        To move it under Kubernetes management run: ${BARBICAN_KEK_PLANNER} --adopt"
            return 0
        fi

        # No kek anywhere and simple_crypto is enabled: deploying now would
        # crashloop. Decide between adopt (data present) and generate (none).
        db_state="$(kek_db_state)"
        kek_log "no kek in Secret or overrides; release=${release} barbican-etc=${etc_exists} kek_data=${db_state}"
        if [[ "$db_state" == "rows" || ( "$db_state" == "unknown" && "$release" == "true" ) ]]; then
            # Case 2
            if [[ "$BARBICAN_KEK_AUTO_ADOPT" != "true" ]]; then
                kek_die "existing barbican data found but no kek is configured. Run
         ${BARBICAN_KEK_PLANNER} --adopt
       to stage the currently deployed kek into ${BARBICAN_KEK_SECRET}, then re-run."
            fi
            kek_adopt
            case $? in
                0) ;;
                2) kek_die "existing barbican data found, but barbican-api has no ready pods, so the
       deployed kek cannot be validated against the database before adopting it.
       This is the state a Gazpacho deploy without a kek leaves behind (pods
       crashlooping on 'SimpleCrypto KEK is undefined'). Roll back to the last
       good revision, then re-run this install; adoption then happens automatically:
           helm -n $(kek_ns) history ${SERVICE_NAME_DEFAULT:-barbican}
           helm -n $(kek_ns) rollback ${SERVICE_NAME_DEFAULT:-barbican} <revision>" ;;
                3) kek_die "existing barbican data found, but the kek in the running Barbican's
       rendered configuration does NOT unwrap the project keys in barbican.kek_data
       (see 'unwrapped N/N' above). The database was wrapped with a different kek
       than this release renders - e.g. a kek line was removed or changed in the
       override files after a rotation, or the DB was restored from elsewhere.
       Nothing was written. Locate the correct kek and confirm it:
           ${BARBICAN_KEK_PLANNER} --validate <kek>
       then set it as conf.barbican.simple_crypto_plugin.kek in your override file
       and re-run this install. Once deployed, move it under Secret management with
           ${BARBICAN_KEK_PLANNER} --adopt" ;;
                *) kek_die "existing barbican data found but the active kek could not be adopted
       (see messages above). Nothing was written." ;;
            esac
        else
            # Case 3 (also recovers a crashlooped first Gazpacho install: the
            # release exists but db-sync never wrapped a single project key).
            if [[ "$BARBICAN_KEK_AUTO_GENERATE" != "true" ]]; then
                kek_die "no kek configured and no barbican data to derive one from (kek_data=${db_state}).
       Create ${BARBICAN_KEK_SECRET} with a 44-char Fernet key (see create-secrets.sh), then re-run."
            fi
            [[ "$db_state" == "unknown" ]] && \
                kek_log "WARNING: could not query barbican.kek_data; no release is installed so a fresh kek is assumed safe"
            kek_log "generating a fresh kek into ${BARBICAN_KEK_SECRET} (no simple_crypto data to protect)"
            kek_write_secret "$(kek_generate)" ""
            generated=true
        fi
        secret_kek="$(kek_secret_field "$BARBICAN_KEK_SECRET" "$BARBICAN_KEK_DATA_KEY")"
        kek_format_ok "$secret_kek" || kek_die "${BARBICAN_KEK_SECRET} still holds no valid kek after adopt/generate"
    fi

    # ---- Secret holds a valid kek: guard the rewrap, then inject ----
    secret_old="$(kek_secret_field "$BARBICAN_KEK_SECRET" "$BARBICAN_KEK_OLD_DATA_KEY")"
    if [[ -n "$override_kek" && "$override_kek" != "$secret_kek" ]]; then
        kek_log "NOTICE: override file kek differs from the Secret; the Secret takes precedence."
    fi
    if [[ "$generated" == "true" ]]; then
        kek_log "fresh kek; db-sync rewrap has no project keys to process."
    elif [[ "$etc_exists" == "true" ]]; then
        local effective="${deployed:-$BARBICAN_WELL_KNOWN_KEK}"
        if [[ "$secret_kek" == "$effective" ]]; then
            kek_log "Secret kek matches the deployed kek; db-sync rewrap is a no-op."
        elif grep -qxF -- "$effective" <<< "$(tr ',' '\n' <<< "${secret_old},${BARBICAN_WELL_KNOWN_KEK}")"; then
            kek_log "WARNING: Secret kek differs from the deployed kek: this deploy performs a"
            kek_log "         ONE-WAY rewrap of every simple_crypto project KEK during db-sync."
            kek_log "         Back up the barbican DB first. Afterwards run"
            kek_log "         ${BARBICAN_KEK_PLANNER} --validate deployed"
            kek_log "         and confirm the db-sync job logs show zero rewrap failures."
        else
            kek_die "Secret kek differs from the deployed kek and the deployed kek is not in
       ${BARBICAN_KEK_SECRET}/${BARBICAN_KEK_OLD_DATA_KEY}: the db-sync rewrap could not unwrap the
       existing project keys and barbican would not start. Do not deploy.
       Stage rotations only with ${BARBICAN_KEK_PLANNER} (--apply), or re-adopt the
       deployed kek with --adopt after deleting the Secret deliberately."
        fi
    elif [[ "$release" == "false" && "$(kek_db_state)" == "rows" ]]; then
        kek_log "WARNING: no barbican release, but barbican.kek_data has simple_crypto rows. db-sync will"
        kek_log "         try to rewrap them from old_keks/upstream default onto the Secret kek; if they"
        kek_log "         were wrapped with another key the db-sync job fails closed (no rows modified)."
    fi

    kek_record_kubesecrets

    set_args+=(--set "conf.barbican.simple_crypto_plugin.kek=${secret_kek}")
    if [[ -n "$secret_old" ]]; then
        # comma is --set list syntax; escape so the whole history survives as one string
        set_args+=(--set-string "conf.simple_crypto_kek_rewrap.old_kek=${secret_old//,/\\,}")
    fi
    # empty old_keks -> chart default old_kek (upstream well-known) applies
}

# ---- direct execution (not sourced) ----
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    case "${1:-}" in
        record)
            [[ -f "$BARBICAN_KEK_KUBESECRETS" ]] || kek_die "${BARBICAN_KEK_KUBESECRETS} does not exist"
            [[ -n "$(kek_secret_field "$BARBICAN_KEK_SECRET" "$BARBICAN_KEK_DATA_KEY")" ]] \
                || kek_die "Secret ${BARBICAN_KEK_SECRET} is absent or empty; nothing to record"
            kek_record_kubesecrets
            kek_log "${BARBICAN_KEK_KUBESECRETS} matches the cluster Secret."
            ;;
        *)
            echo "usage: $0 record    # sync ${BARBICAN_KEK_SECRET} into ${BARBICAN_KEK_KUBESECRETS}" >&2
            echo "       (otherwise this file is sourced by bin/install-barbican.sh)" >&2
            exit 2
            ;;
    esac
fi
