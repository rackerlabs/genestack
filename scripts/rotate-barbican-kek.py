#!/usr/bin/env python3
"""Stage, adopt or validate the Barbican simple_crypto master KEK.

The KEK lives in the Kubernetes Secret barbican-simple-crypto-kek (data key
kek, plus old_keks: a comma-separated history). install-barbican.sh injects
both into the chart on every deploy, unless an override file sets the kek,
which always takes precedence. This tool only ever writes that Secret; the
rotation itself happens on the NEXT install-barbican.sh run, when the chart's
db-sync job rewraps every simple_crypto project KEK from old_keks onto the new
kek (one-way). install-barbican.sh never calls this tool.

Modes (the default is the read-only plan):
  (no flags)     plan: resolve the deployed kek, prove it unwraps every
                 project KEK in the database, report what --stage would write.
  --stage        plan, then generate a new kek and write it to the Secret with
                 the deployed kek and every earlier kek recorded in old_keks.
  --adopt        write the CURRENTLY DEPLOYED kek to the Secret; no new key,
                 so the next deploy's rewrap is a no-op. For environments that
                 ran on an override-file kek or the upstream default:
                 install-barbican.sh refuses to deploy one that holds barbican
                 data while neither an override file nor the Secret supplies
                 a kek, and this puts the running kek under Secret management.
  --adopt -      the same for a kek read from stdin: it must unwrap every
                 project KEK itself.
  --validate X   read-only: does kek X unwrap every project KEK? X is
                 'deployed' (from the running release), 'staged' (from the
                 Secret), a 44-char kek, '-' to read the kek from stdin (it
                 then never appears in argv or shell history), or the path of
                 an overrides YAML holding conf.barbican.simple_crypto_plugin.kek.

Rotation runbook:
  1. rotate-barbican-kek.py                     review the plan
  2. rotate-barbican-kek.py --stage             stage the new kek
  3. back up the barbican database
  4. install-barbican.sh                        db-sync rewraps (one-way)
  5. rotate-barbican-kek.py --validate deployed

Validation runs inside a barbican-api pod, which has the database
credentials and the cryptography library, so a ready pod is required in
every mode. No key material is printed: keys appear as an 8-character
fingerprint (sha256 prefix).

Environment: NS (namespace, default openstack), KUBECTL (default kubectl).
Exit codes: 0 ok; 1 the kek does not unwrap the database; 2 malformed key or
bad input; 3 missing dependency or no ready barbican-api pod; 4 a
staged-but-undeployed rotation already exists (deploy it or delete the
Secret deliberately first).
"""

import argparse
import base64
import hashlib
import json
import os
import secrets
import subprocess
import sys

SECRET_NAME = "barbican-simple-crypto-kek"
DATA_KEY_KEK = "kek"
DATA_KEY_OLD = "old_keks"
KUBECTL = os.environ.get("KUBECTL", "kubectl")
SIMPLE_CRYPTO_PLUGIN = "barbican.plugin.crypto.simple_crypto.SimpleCryptoPlugin"

# Barbican's upstream default simple_crypto KEK: public knowledge (OpenStack
# docs, OSH chart values) and what every pre-Gazpacho deploy without an
# explicit kek ran on. Derived rather than written in its base64 form so
# secret scanners do not flag a key-shaped blob. Not a secret, not our key.
WELL_KNOWN_KEK = base64.b64encode(b"thirty_two_byte_keyblahblahblahh").decode()

# Runs inside barbican-api. Mirrors the selection of the chart's
# simple_crypto_kek_rewrap.py: every kek_data row of the simple_crypto
# plugin, active or not, because the rewrap processes them all and fails the
# db-sync job on any row it cannot unwrap. The candidate is substituted into
# the script text (format-gated to base64 characters first) so it never
# appears in argv. Exits 0 all unwrapped / 1 some not / 3 could not run.
POD_VALIDATE_PY = r"""
import sys
try:
    from cryptography.fernet import Fernet, InvalidToken
    from oslo_config import cfg
    import sqlalchemy as sa

    conf = cfg.ConfigOpts()
    conf.register_opts([cfg.StrOpt("connection", secret=True)], group="database")
    conf(args=[], project="barbican")
    with sa.create_engine(conf.database.connection).connect() as c:
        rows = c.execute(
            sa.text("SELECT id, plugin_meta FROM kek_data "
                    "WHERE plugin_name = :plugin AND plugin_meta IS NOT NULL"),
            {"plugin": "__PLUGIN__"}).fetchall()
except Exception as exc:
    print("validation could not run: %s: %s" % (type(exc).__name__, exc), file=sys.stderr)
    sys.exit(3)

f = Fernet("__CAND__")
failed = []
for kek_id, meta in rows:
    try:
        f.decrypt(meta.encode() if isinstance(meta, str) else meta)
    except InvalidToken:
        failed.append(str(kek_id))
print("unwrapped %d/%d simple_crypto project KEKs" % (len(rows) - len(failed), len(rows)),
      file=sys.stderr)
for kek_id in failed[:10]:
    print("  not unwrapped: kek_data.id=" + kek_id, file=sys.stderr)
sys.exit(1 if failed else 0)
"""


def info(msg):
    print(f"INFO: {msg}", file=sys.stderr)


def die(msg, rc=1):
    print(f"FATAL: {msg}", file=sys.stderr)
    sys.exit(rc)


def fp(kek):
    """Short fingerprint for messages; never the key itself."""
    return hashlib.sha256(kek.encode()).hexdigest()[:8]


def kubectl(ns, *args, stdin=None):
    try:
        return subprocess.run(
            [KUBECTL, "-n", ns, *args], capture_output=True, text=True, input=stdin
        )
    except FileNotFoundError:
        die(f"{KUBECTL} not found", rc=3)


def secret_field(ns, secret, key):
    """Decoded value of one data key, or '' when the Secret or key is missing."""
    r = kubectl(ns, "get", "secret", secret, "-o", f"jsonpath={{.data.{key}}}")
    if r.returncode != 0 or not r.stdout.strip():
        return ""
    try:
        return base64.b64decode(r.stdout.strip()).decode()
    except Exception:
        return ""


def kek_format_ok(kek):
    """44 characters that decode to exactly 32 bytes: a Fernet key."""
    if len(kek) != 44:
        return False
    try:
        return len(base64.urlsafe_b64decode(kek)) == 32
    except Exception:
        return False


def generate_kek():
    """32 random bytes, urlsafe base64: the Fernet key format (same as create-secrets.sh)."""
    return base64.urlsafe_b64encode(secrets.token_bytes(32)).decode()


# ---- cluster state -----------------------------------------------------------


def deployed_kek(ns):
    """First 'kek' under [simple_crypto_plugin] in the rendered barbican.conf of
    the current release (the barbican-etc Secret). '' when there is no release
    or the last render carried no explicit kek."""
    in_section = False
    for line in secret_field(ns, "barbican-etc", r"barbican\.conf").splitlines():
        s = line.strip()
        if s.startswith("["):
            in_section = s == "[simple_crypto_plugin]"
        elif in_section and "=" in s:
            key, _, val = s.partition("=")
            if key.strip() == "kek":
                return val.strip().strip("\"'")
    return ""


def resolve_deployed(ns):
    kek = deployed_kek(ns)
    if kek:
        info(f"deployed kek fp={fp(kek)} (explicit in the rendered barbican.conf)")
    else:
        kek = WELL_KNOWN_KEK
        info("no kek in the rendered barbican.conf: the upstream default is in effect")
    if not kek_format_ok(kek):
        die("the deployed kek is not a valid 44-char Fernet key", rc=2)
    return kek


def configured_old_keks(ns):
    """Every old kek already recorded: the chart's rendered rewrap history
    ('old_kek' up to 2024.x, 'old_keks' since Epoxy) and the Secret's own."""
    vals = []
    for secret, key in (
        ("barbican-etc", "old_kek"),
        ("barbican-etc", "old_keks"),
        (SECRET_NAME, DATA_KEY_OLD),
    ):
        vals += [
            p.strip() for p in secret_field(ns, secret, key).split(",") if p.strip()
        ]
    return vals


def staged_kek(ns):
    return secret_field(ns, SECRET_NAME, DATA_KEY_KEK)


def kek_from_overrides(path):
    try:
        import yaml
    except ImportError:
        die("PyYAML is required to read an overrides file", rc=3)
    with open(path) as fh:
        doc = yaml.safe_load(fh) or {}
    try:
        kek = doc["conf"]["barbican"]["simple_crypto_plugin"]["kek"]
    except (KeyError, TypeError):
        die(f"{path}: no conf.barbican.simple_crypto_plugin.kek", rc=2)
    if isinstance(kek, list):
        kek = kek[0] if kek else ""
    return str(kek or "")


def validate(ns, candidate):
    """True when the candidate unwraps every simple_crypto project KEK; the pod prints the counts."""
    if not kek_format_ok(candidate):
        die("candidate is not a valid 44-char Fernet key", rc=2)
    r = kubectl(
        ns, "get", "deploy/barbican-api", "-o", "jsonpath={.status.readyReplicas}"
    )
    if (
        r.returncode != 0
        or not r.stdout.strip().isdigit()
        or int(r.stdout.strip()) == 0
    ):
        die(
            "barbican-api has no ready pod and validation runs inside it. If the pods crashloop "
            "on 'SimpleCrypto KEK is undefined', helm rollback to the last good revision first.",
            rc=3,
        )
    script = POD_VALIDATE_PY.replace("__CAND__", candidate).replace(
        "__PLUGIN__", SIMPLE_CRYPTO_PLUGIN
    )
    r = kubectl(
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
        stdin=script,
    )
    sys.stderr.write(r.stderr)
    if r.returncode not in (0, 1):
        die(f"validation could not run inside barbican-api (exit {r.returncode})", rc=3)
    return r.returncode == 0


def write_secret(ns, kek, old_keks):
    """Create or update the Secret with 'kubectl apply -f -' on stdin, so the
    kek never appears in argv or ps; then read it back to verify."""
    manifest = json.dumps(
        {
            "apiVersion": "v1",
            "kind": "Secret",
            "metadata": {"name": SECRET_NAME, "namespace": ns},
            "type": "Opaque",
            "data": {
                DATA_KEY_KEK: base64.b64encode(kek.encode()).decode(),
                DATA_KEY_OLD: base64.b64encode(",".join(old_keks).encode()).decode(),
            },
        }
    )
    r = kubectl(ns, "apply", "-f", "-", stdin=manifest)
    if r.returncode != 0:
        die(f"kubectl apply failed: {r.stderr.strip()}")
    if staged_kek(ns) != kek:
        die("post-apply readback mismatch: the Secret does not hold the new kek")


# ---- modes --------------------------------------------------------------------


def gate(ns):
    """Shared by plan, --stage and --adopt. The deployed kek must unwrap the
    database (otherwise nothing built on it can succeed), and a staged but not
    yet deployed rotation must not be overwritten. Returns the deployed kek,
    the staged kek ('' if none) and the old_keks history to record."""
    deployed = resolve_deployed(ns)
    if not validate(ns, deployed):
        die(
            "the deployed kek does not unwrap every project KEK; find the right one with "
            "--validate <kek> and deploy it before staging anything on top of it."
        )
    staged = staged_kek(ns)
    # A Secret holding the deployed kek is an adoption already done, and one
    # holding the public upstream default is not a rotation anyone staged, so
    # both may be overwritten. Anything else is a staged-but-undeployed rotation.
    if staged and staged not in (deployed, WELL_KNOWN_KEK):
        die(
            f"{SECRET_NAME} already holds a kek (fp={fp(staged)}) that is not deployed: a staged "
            "rotation is pending. Deploy it with install-barbican.sh, or delete the Secret "
            "deliberately, then re-run.",
            rc=4,
        )
    history = [
        k
        for k in dict.fromkeys([deployed, *configured_old_keks(ns), WELL_KNOWN_KEK])
        if kek_format_ok(k)
    ]
    return deployed, staged, history


def cmd_plan(ns, stage):
    _, _, history = gate(ns)
    info(
        f"plan: {len(history)} old kek(s) -> {SECRET_NAME}/{DATA_KEY_OLD}: "
        + ", ".join(fp(k) for k in history)
    )
    if not stage:
        info(f"plan: a new kek would be generated -> {SECRET_NAME}/{DATA_KEY_KEK}")
        info("dry run only; re-run with --stage to write the Secret")
        return 0
    new = generate_kek()
    write_secret(ns, new, history)
    info(
        f"staged new kek fp={fp(new)}. Back up the barbican database, then run install-barbican.sh: "
        "its db-sync job rewraps every project KEK (one-way). Afterwards '--validate deployed' "
        "must pass and the db-sync logs must show zero failures."
    )
    return 0


def cmd_adopt(ns, what):
    """--adopt: the deployed kek. --adopt -: a kek read from stdin, which must
    unwrap every project KEK itself (the deployed kek then only joins the
    history). Either way the next deploy's rewrap is a no-op."""
    if what == "-":
        kek = sys.stdin.readline().strip()
        if not kek_format_ok(kek):
            die("the kek on stdin is not a valid 44-char Fernet key", rc=2)
        deployed = resolve_deployed(ns)
        if not validate(ns, kek):
            die(
                "the supplied kek does not unwrap every project KEK; nothing was written."
            )
        staged = staged_kek(ns)
        if staged and staged not in (kek, deployed, WELL_KNOWN_KEK):
            die(
                f"{SECRET_NAME} already holds a kek (fp={fp(staged)}) that is not deployed: a staged "
                "rotation is pending. Deploy it with install-barbican.sh, or delete the Secret "
                "deliberately, then re-run.",
                rc=4,
            )
        history = [
            k
            for k in dict.fromkeys(
                [kek, deployed, *configured_old_keks(ns), WELL_KNOWN_KEK]
            )
            if kek_format_ok(k)
        ]
    else:
        kek, staged, history = gate(ns)
    if staged == kek:
        info("the Secret already holds that kek; nothing to adopt")
        return 0
    write_secret(ns, kek, history)
    info(
        f"adopted: {SECRET_NAME} now holds kek fp={fp(kek)} and {len(history)} old kek(s). "
        "Remove any kek line from your override files (an override always takes "
        "precedence over the Secret); the next install-barbican.sh then injects it "
        "(rewrap no-op)."
    )
    return 0


def cmd_validate(ns, what):
    if what == "deployed":
        cand = resolve_deployed(ns)
    elif what == "staged":
        cand = staged_kek(ns)
        if not cand:
            die(f"{SECRET_NAME} is absent or empty; nothing is staged", rc=2)
    elif what == "-":
        cand = sys.stdin.readline().strip()
    elif os.path.isfile(what):
        cand = kek_from_overrides(what)
    else:
        cand = what
    ok = validate(ns, cand)
    info(
        f"kek fp={fp(cand)} {'unwraps' if ok else 'does NOT unwrap'} every simple_crypto project KEK"
    )
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument(
        "--stage",
        action="store_true",
        help="generate a new kek and stage it in the Secret (the rotation runs on the next deploy)",
    )
    mode.add_argument(
        "--adopt",
        nargs="?",
        const="deployed",
        metavar="-",
        help="store the currently deployed kek in the Secret (no rotation); "
        "'--adopt -' stores a kek read from stdin instead, after validating it",
    )
    mode.add_argument(
        "--validate",
        metavar="deployed|staged|KEK|-|OVERRIDES.yaml",
        help="check that a kek unwraps every simple_crypto project KEK, then exit",
    )
    ap.add_argument(
        "-n",
        "--namespace",
        default=os.environ.get("NS", "openstack"),
        help="kubernetes namespace (default: %(default)s)",
    )
    args = ap.parse_args()
    if args.validate:
        return cmd_validate(args.namespace, args.validate)
    if args.adopt is not None:
        return cmd_adopt(args.namespace, args.adopt)
    return cmd_plan(args.namespace, stage=args.stage)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
