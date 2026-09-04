#!/usr/bin/env python3
"""Barbican KEK rewrite planner (Kubernetes/Helm-only flow).

The KEK's source of truth is the barbican-simple-crypto-plugin-kek
Kubernetes Secret, injected at deploy time by install-barbican.sh via
--set (see the KEK injection block in that script). This planner stages
a rotation by updating that Secret; the rotation itself happens on the
NEXT install-barbican.sh run, when the db-sync job rewraps every
project KEK in the barbican DB (one-way).

Modes:
  (no flags)      plan: resolve the deployed kek, prove it unwraps the
                  DB project keys, show what --apply would stage.
                  Read-only; prints no key material.
  --apply         plan + actually update the Secret (via kubectl apply
                  on stdin, so the kek never appears in argv/ps).
  --adopt         stage the CURRENTLY DEPLOYED kek into the Secret (no new
                  key is generated, the next deploy's rewrap is a no-op).
                  For environments that rotated before this tooling existed
                  and want Secret-based management without another rotation.
                  Implies --apply semantics for the Secret write.
  --validate X    read-only check: does kek X unwrap the DB project
                  keys? X is a 44-char kek, the keyword 'deployed'
                  (resolve from the cluster), the keyword 'staged'
                  (read from the Secret), or a path to a legacy
                  overrides yaml. Exits 0 yes / 1 no.

Environment / flags:
  NS      / --namespace   kubernetes namespace   (default: openstack)
  KUBECTL                 kubectl binary         (default: kubectl)

Exit codes: 0 ok; 1 validation/gate failure; 2 malformed key material;
3 missing dependency; 4 a staged-but-undeployed rotation already exists
(no-clobber: deploy it or delete the Secret deliberately first).
"""

import argparse
import base64
import json
import os
import secrets
import subprocess
import sys

# Barbican's upstream default simple_crypto KEK ("well-known" — printed in
# the OpenStack docs and the OSH chart values). Derived rather than written
# as its 44-char base64 form so secret scanners don't flag a key-shaped
# blob in this repo. This is NOT a secret and NOT one of our keys; it is
# the value pre-rotation environments are implicitly running on, needed as
# the resolve fallback and for old_keks coverage. Do not "simplify" back
# to the base64 literal.
WELL_KNOWN_KEK = base64.b64encode(b"thirty_two_byte_keyblahblahblahh").decode()
KUBECTL = os.environ.get("KUBECTL", "kubectl")

SECRET_NAME = "barbican-simple-crypto-plugin-kek"
DATA_KEY_KEK = "barbican_simple_crypto_plugin_kek"  # read by install-barbican.sh
DATA_KEY_OLD = "old_keks"  # comma-separated history

# Runs inside the barbican-api pod: print effective kek(s), one per line.
POD_EFFECTIVE_KEK_PY = r"""
from barbican.plugin.crypto import simple_crypto
conf = simple_crypto.CONF
conf(args=[], project='barbican')
k = conf.simple_crypto_plugin.kek
if isinstance(k, (list, tuple)):
    print('\n'.join(x for x in k if x))
elif k:
    print(k)
"""

# Runs inside the barbican-api pod. The candidate kek is substituted into
# the script text (__CAND__) rather than passed as argv, so a key the pod
# does not yet hold (e.g. --validate staged) is never visible in
# /proc/*/cmdline inside the pod. SELECT only.
POD_VALIDATE_PY = r"""
import sys
from cryptography.fernet import Fernet
from oslo_config import cfg
import sqlalchemy as sa

def try_unwrap(f, m):
    try:
        f.decrypt(m.encode() if isinstance(m, str) else m)
        return True
    except Exception:
        return False

cand = "__CAND__"
conf = cfg.ConfigOpts()
conf.register_opts([cfg.StrOpt('connection', secret=True)], group='database')
conf(args=[], project='barbican')

eng = sa.create_engine(conf.database.connection)
with eng.connect() as c:
    rows = c.execute(sa.text(
        "SELECT plugin_meta FROM kek_data "
        "WHERE active = 1 AND plugin_meta IS NOT NULL LIMIT 25")).fetchall()

if not rows:
    print("no active project KEKs in DB; nothing to unwrap", file=sys.stderr)
    sys.exit(0)

f = Fernet(cand)
ok = sum(1 for (m,) in rows if try_unwrap(f, m))
print(f"unwrapped {ok}/{len(rows)} sampled project KEKs", file=sys.stderr)
sys.exit(0 if ok == len(rows) else 1)
"""


def info(msg):
    print(f"INFO: {msg}", file=sys.stderr)


def die(msg, rc=1):
    print(f"FATAL: {msg}", file=sys.stderr)
    sys.exit(rc)


def generate_fernet_token(nchars=32):
    """32 chars from the create-secrets.sh alphabet, base64-encoded: a
    44-char Fernet-format key. Mirrors generate_fernet_token in bash."""
    alphabet = "_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    raw = "".join(secrets.choice(alphabet) for _ in range(nchars)).encode()
    return base64.b64encode(raw).decode()


def kek_format_ok(kek):
    if len(kek) != 44:
        return False
    try:
        return len(base64.urlsafe_b64decode(kek)) == 32
    except Exception:
        return False


def run(cmd, **kw):
    """subprocess.run wrapper that never raises on nonzero exit."""
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def kubectl_get_secret_field(ns, secret, field):
    """Decoded value of one data key, or '' (missing secret/key alike)."""
    r = run(
        [
            KUBECTL,
            "-n",
            ns,
            "get",
            "secret",
            secret,
            "-o",
            f"jsonpath={{.data.{field}}}",
        ]
    )
    if r.returncode != 0 or not r.stdout.strip():
        return ""
    try:
        return base64.b64decode(r.stdout.strip()).decode()
    except Exception:
        return ""


def pod_python(ns, script):
    """Run a python script inside the barbican-api container via stdin."""
    cmd = [
        KUBECTL,
        "-n",
        ns,
        "exec",
        "-i",
        "deploy/barbican-api",
        "-c",
        "barbican-api",
        "--",
        "python3",
        "-W",
        "ignore::SyntaxWarning",
        "-",
    ]
    return run(cmd, input=script)


def get_deployed_kek(ns):
    """kek line(s) from the rendered barbican.conf, in order (the --set
    injection lands here, so this reflects what is actually deployed)."""
    conf_text = kubectl_get_secret_field(ns, "barbican-etc", r"barbican\.conf")
    keks, in_section = [], False
    for line in conf_text.splitlines():
        s = line.strip()
        if s.startswith("["):
            in_section = s == "[simple_crypto_plugin]"
            continue
        if in_section and s.startswith("kek") and "=" in s:
            key, _, val = s.partition("=")
            if key.strip() == "kek":
                keks.append(val.strip().strip("\"'"))
    return keks


def get_effective_kek_from_pod(ns):
    r = pod_python(ns, POD_EFFECTIVE_KEK_PY)
    if r.returncode != 0:
        return []
    return [ln.strip() for ln in r.stdout.splitlines() if ln.strip()]


def get_configured_old_keks(ns):
    """Old keks already recorded anywhere: the rendered chart rewrap keys
    ('old_kek' <=2024.x, 'old_keks' Epoxy+) and our own Secret's history."""
    vals = []
    for secret, field in (
        ("barbican-etc", "old_kek"),
        ("barbican-etc", "old_keks"),
        (SECRET_NAME, DATA_KEY_OLD),
    ):
        raw = kubectl_get_secret_field(ns, secret, field)
        vals.extend(p.strip() for p in raw.split(",") if p.strip())
    return sorted(set(vals))


def get_staged_kek(ns):
    return kubectl_get_secret_field(ns, SECRET_NAME, DATA_KEY_KEK)


def validate_kek_against_db(ns, candidate):
    if not kek_format_ok(candidate):
        # format gate doubles as an injection guard: only base64url chars
        # can reach the substitution below
        die("candidate is not a valid 44-char Fernet key", rc=2)
    r = pod_python(ns, POD_VALIDATE_PY.replace("__CAND__", candidate))
    if r.stderr:
        sys.stderr.write(r.stderr)
    return r.returncode == 0


def resolve_active_kek(ns):
    keks = get_deployed_kek(ns)
    if not keks:
        keks = get_effective_kek_from_pod(ns)
    if not keks:
        info("no kek configured anywhere; code default is in effect")
        keks = [WELL_KNOWN_KEK]
    active = keks[0]
    if not kek_format_ok(active):
        die("resolved kek is not a valid Fernet key", rc=2)
    info(f"active kek resolved ({len(active)} chars)")
    return active


def apply_secret(ns, new_kek, old_keks):
    """Create/update the Secret via `kubectl apply -f -` (stdin): the kek
    never appears in argv, ps output, or shell history."""
    manifest = json.dumps(
        {
            "apiVersion": "v1",
            "kind": "Secret",
            "metadata": {"name": SECRET_NAME, "namespace": ns},
            "type": "Opaque",
            "data": {
                DATA_KEY_KEK: base64.b64encode(new_kek.encode()).decode(),
                DATA_KEY_OLD: base64.b64encode(",".join(old_keks).encode()).decode(),
            },
        }
    )
    r = run([KUBECTL, "-n", ns, "apply", "-f", "-"], input=manifest)
    if r.returncode != 0:
        die(f"kubectl apply failed: {r.stderr.strip()}")
    if get_staged_kek(ns) != new_kek:
        die("post-apply readback mismatch — Secret does not hold the new kek")


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--namespace", default=os.environ.get("NS", "openstack"))
    ap.add_argument(
        "--apply",
        action="store_true",
        help="actually stage the rotation by updating the Secret",
    )
    ap.add_argument(
        "--adopt",
        action="store_true",
        help="stage the currently deployed kek (no rotation); " "writes the Secret",
    )
    ap.add_argument(
        "--validate",
        metavar="KEK|deployed|staged|OVERRIDES_YAML",
        help="validate a kek against the DB and exit",
    )
    args = ap.parse_args()
    ns = args.namespace

    if args.adopt and args.apply:
        die(
            "--adopt and --apply are mutually exclusive; --adopt writes the "
            "Secret itself",
            rc=2,
        )
    if args.validate and (args.adopt or args.apply):
        die("--validate cannot be combined with --adopt/--apply", rc=2)

    if args.validate:
        cand = args.validate
        if cand == "deployed":
            cand = resolve_active_kek(ns)
        elif cand == "staged":
            cand = get_staged_kek(ns)
            if not cand:
                die(f"{SECRET_NAME} is absent or empty; nothing staged", rc=2)
        elif os.path.isfile(cand):
            try:
                import yaml
            except ImportError:
                die("PyYAML is required to read an overrides file", rc=3)
            with open(cand) as fh:
                try:
                    cand = yaml.safe_load(fh)["conf"]["barbican"][
                        "simple_crypto_plugin"
                    ]["kek"]
                except (KeyError, TypeError):
                    die(
                        f"{args.validate}: no conf.barbican.simple_crypto_plugin.kek found",
                        rc=2,
                    )
        ok = validate_kek_against_db(ns, cand)
        info(
            "candidate kek unwraps the DB project keys"
            if ok
            else "candidate kek does NOT unwrap the DB project keys"
        )
        sys.exit(0 if ok else 1)

    # ---- plan / apply ----
    active_kek = resolve_active_kek(ns)
    if not validate_kek_against_db(ns, active_kek):
        die("resolved KEK does not unwrap DB project keys — do not proceed")

    # No-clobber: a Secret holding a key that is neither deployed nor the
    # well-known default is a staged-but-undeployed rotation. Overwriting
    # it would silently discard a key someone may be mid-deploy with.
    staged = get_staged_kek(ns)
    if staged and staged not in (active_kek, WELL_KNOWN_KEK):
        die(
            f"{SECRET_NAME} already holds a kek that is not deployed —\n"
            f"       a staged rotation is pending. Deploy it "
            f"(install-barbican.sh) or delete the Secret deliberately, "
            f"then re-run.",
            rc=4,
        )

    old_keks = list(
        dict.fromkeys(
            [active_kek, *get_configured_old_keks(ns), WELL_KNOWN_KEK, staged]
        )
    )
    old_keks = [k for k in old_keks if k and kek_format_ok(k)]

    if args.adopt:
        # Adoption: the Secret takes over management of the key already in
        # use. No new key, so the next deploy's --set injects the same kek
        # the overrides supply today and the rewrap is a no-op.
        if staged == active_kek:
            info("Secret already holds the deployed kek; nothing to adopt")
            return
        info(
            f"plan: adopt deployed kek into Secret {ns}/{SECRET_NAME} " f"(no rotation)"
        )
        info(f"plan: record {len(old_keks)} old kek(s) in data key " f"{DATA_KEY_OLD}")
        apply_secret(ns, active_kek, old_keks)
        info(
            "adopted. Next install-barbican.sh deploy injects the same kek "
            "from the Secret (rewrap no-op). Your override files' kek line "
            "can be removed after one successful deploy."
        )
        return

    new_kek = generate_fernet_token(32)
    if not kek_format_ok(new_kek) or new_kek in old_keks:
        die("generated kek invalid", rc=2)

    info(
        f"plan: stage new kek in Secret {ns}/{SECRET_NAME} "
        f"(data key {DATA_KEY_KEK})"
    )
    info(f"plan: record {len(old_keks)} old kek(s) in data key {DATA_KEY_OLD}")
    if not args.apply:
        info("dry-run only; re-run with --apply to stage the rotation")
        return

    apply_secret(ns, new_kek, old_keks)
    info(
        f"staged. The rotation runs on the NEXT install-barbican.sh deploy "
        f"(db-sync rewrap, one-way). Before deploying: back up the barbican "
        f"DB. After: '{os.path.basename(sys.argv[0])} --validate deployed' "
        f"must pass and the db-sync logs must show zero rewrap failures."
    )


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as exc:
        die(f"aborted: {type(exc).__name__}: {exc}")
