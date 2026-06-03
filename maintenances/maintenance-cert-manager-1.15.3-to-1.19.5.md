# Component Maintenance: cert-manager `v1.15.3` to `v1.19.5`

# Notes

`(opt)` refers to `/opt`, the standard install path for _Genestack_.

`(etc)` refers to `/etc`, the standard override path for _Genestack_.

This runbook upgrades _cert-manager_ from `v1.15.3` to `v1.19.5` and
converts the installation to the Genestack chart-managed installation path.
In older or existing environments, _cert-manager_ may still have been installed
by _kubespray_. The first install step intentionally uses _Helm_ with
`--take-ownership` so that _Helm_ adopts the existing resources instead of
requiring an uninstall and reinstall.

Do not uninstall _cert-manager_ as part of this maintenance. Treat this as an
adoption and forward-upgrade maintenance, not as a rebuild.

_cert-manager_ `v1.18.x` changed the default value of
`Certificate.spec.privateKey.rotationPolicy` from `Never` to `Always`. That is
a reasonable default for ordinary leaf certificates, but it is not desired for
Genestack CA certificates such as `public-endpoint-ca-cert`. This runbook
patches that CA certificate before crossing the `v1.18.x` boundary, then
verifies the setting again at the end.

The cert-manager support scripts used by this runbook are expected to exist in:

```text
/opt/genestack/scripts/cert-manager-support/
```

# Validation

- Validated source version: _cert-manager_ `v1.15.3`
- Validated target version: _cert-manager_ `v1.19.5`
- Validated platform dependency:
  - Genestack deployment using `/opt/genestack` and `/etc/genestack`
  - `/opt/genestack` checked out to a ref containing the `v1.19.5` cert-manager
    change set or its merged equivalent
  - `/etc/genestack` populated for the target site
  - _Helm_ `3.17.x` or newer `3.x` with `--take-ownership`
  - `kubectl`, `helm`, `jq`, `yq`, `grep`, `sed`, `curl`, and `cmctl`
- Validated install path:
  - _cert-manager_ starts at `v1.15.3`
  - _kubespray_ no longer manages _cert-manager_
  - Genestack installs the _cert-manager_ chart from the OCI chart source

# Supported upgrade path

Use this validated path for this maintenance:

```text
v1.15.3 current state
v1.15.3 Helm takeover
v1.16.5
v1.17.4
v1.18.6
v1.19.5
```

Do not skip the intermediate versions in this runbook. The first `v1.15.3`
step does not upgrade the application version. It adopts the existing
installation into the Genestack Helm release state.

# Major operational risks for this maintenance

- _cert-manager_ controller, cainjector, and webhook pods will restart during
  each upgrade hop.
- Certificate issuance and renewal can be delayed while the webhook or
  controller restarts.
- Failed _Helm_ ownership adoption can leave the release incomplete until the
  adoption issue is corrected and the install command is re-run.
- Leaving `cert_manager_enabled: true` in the _kubespray_ inventory can cause
  _kubespray_ and Genestack _Helm_ management to fight over the same component.
- The `v1.18.x` private key rotation default can rotate CA private keys unless
  important CA certificates explicitly set `rotationPolicy: Never`.
- Repeated test renewals against Let's Encrypt can hit public ACME rate limits.
- Rollback is not the preferred recovery path after adoption. Prefer fixing the
  failed step and continuing forward to the target version.

# Goal

Upgrade _cert-manager_ from `v1.15.3` to `v1.19.5`, transfer ownership to the
Genestack Helm-managed installation path, preserve Genestack CA private key
behavior, verify _cert-manager_ API health after each version hop, and confirm
certificate renewal still works after the upgrade.

# Prep

## Deployment Node

Use the standard Genestack deployment host or bastion that has:

- `kubectl` access to the target cluster
- `helm`, `jq`, `yq`, `grep`, `sed`, `curl`, and `cmctl`
- `/opt/genestack` checked out to the approved Genestack ref
- `/etc/genestack` populated for the target site
- access to the site overrides repository, if `/etc/genestack` is backed by one

**RUN**: create a working directory for this maintenance.

```bash
# RUN Create a working directory for this maintenance
export MAINT_DIR=/home/ubuntu/cert-manager-1.19.5-maint
mkdir -p "$MAINT_DIR"
```

## Verify current component health

**RUN**: verify current _cert-manager_ workloads.

```bash
# RUN Verify current cert-manager workloads
kubectl -n cert-manager get deployment,pods
```

Example output/expect:

```text
NAME                                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/cert-manager              1/1     1            1           5d20h
deployment.apps/cert-manager-cainjector   1/1     1            1           5d20h
deployment.apps/cert-manager-webhook      1/1     1            1           5d20h

NAME                                           READY   STATUS    RESTARTS        AGE
pod/cert-manager-67d979dd76-5r47k              1/1     Running   4 (5d20h ago)   5d20h
pod/cert-manager-cainjector-866c785698-rx7dz   1/1     Running   0               5d20h
pod/cert-manager-webhook-776f467f9d-zbd5l      1/1     Running   0               5d20h
```

Restore health before continuing if any _cert-manager_ workload is not ready.

**RUN**: verify the current _cert-manager_ controller image.

```bash
# RUN Verify the current cert-manager image version
kubectl -n cert-manager get deployment cert-manager \
  -o jsonpath='{range .spec.template.spec.containers[*]}{.name}{"\t"}{.image}{"\n"}{end}'
```

Example output/expect:

```text
cert-manager    quay.io/jetstack/cert-manager-controller:v1.15.3
```

If the current version is not `v1.15.3`, stop and reassess. This runbook is
for the validated `v1.15.3` to `v1.19.5` path.

**RUN**: verify the _cert-manager_ API is currently usable.

```bash
# RUN Verify cert-manager API readiness
cmctl check api --wait=2m
```

Example output/expect:

```text
The cert-manager API is ready
```

## Verify current cluster or platform health

**RUN**: verify node health.

```bash
# RUN Verify current node health
kubectl get nodes
```

Example output/expect:

```text
NAME                                  STATUS   ROLES                  AGE   VERSION
hyperconverged-certmgr-0.cluster.local Ready   control-plane,worker   35d   v1.33.5
hyperconverged-certmgr-1.cluster.local Ready   control-plane,worker   35d   v1.33.5
hyperconverged-certmgr-2.cluster.local Ready   control-plane,worker   35d   v1.33.5
```

Restore health before continuing if any node is not `Ready`.

**RUN**: record pods in bad states.

```bash
# RUN Check for pods in bad states
kubectl get pods -A --no-headers | awk '$4 != "Running" && $4 != "Completed" {print}'
```

Example output/expect:

```text
# No output is expected on a clean cluster.
```

Some unrelated non-running pods may be known issues. Document them in the
maintenance log before continuing.

## Verify current Helm state

**RUN**: check whether _cert-manager_ already has a _Helm_ release.

```bash
# RUN Check current Helm release state
helm -n cert-manager list --filter '^cert-manager$'
```

Example output for an environment that is not yet Helm-managed:

```text
NAME    NAMESPACE       REVISION        UPDATED STATUS  CHART   APP VERSION
```

Example output for an environment already Helm-managed:

```text
NAME          NAMESPACE     REVISION  UPDATED                                 STATUS    CHART                  APP VERSION
cert-manager  cert-manager  1         2026-05-28 19:22:12.844935 +0000 UTC   deployed  cert-manager-v1.15.3   v1.15.3
```

Genestack did not use a chart-based installation of cert-manager before adopting
cert-manager v1.19.x, so you should not see a chart here at less than
v1.19.x. For v1.19.x, you can simply perform the CA key rotation portion of
this maintenance. This would only apply to recent or new installations.

# Configuration Review

## Verify `/etc/genestack/kustomize/cert-manager`

The Genestack _cert-manager_ install script uses the Genestack post-renderer.
Most environments need the site-level `cert-manager` kustomize directory in
`/etc/genestack` even if it only points back to the Genestack base.

**RUN**: check whether the directory already exists.

```bash
# RUN Check cert-manager kustomize directory
ls -lR /etc/genestack/kustomize/cert-manager
```

Example output/expect:

```text
/etc/genestack/kustomize/cert-manager:
total 4
lrwxrwxrwx 1 ubuntu ubuntu   47 Jun  1 18:14 base -> /opt/genestack/base-kustomize/cert-manager/base
drwxrwxr-x 2 ubuntu ubuntu 4096 Jun  1 18:14 overlay

/etc/genestack/kustomize/cert-manager/overlay:
total 4
-rw-rw-r-- 1 ubuntu ubuntu 87 Jun  1 18:14 kustomization.yaml
```

**RUN**: if it does not exist, create the standard minimal overlay.

```bash
# RUN Create minimal cert-manager kustomize overlay if needed
sudo mkdir -p /etc/genestack/kustomize/cert-manager/overlay
sudo ln -sfn /opt/genestack/base-kustomize/cert-manager/base \
  /etc/genestack/kustomize/cert-manager/base

cat > /tmp/cert-manager-kustomization.yaml <<'EOF_KUSTOMIZE'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../base
EOF_KUSTOMIZE

sudo install -o root -g root -m 0644 /tmp/cert-manager-kustomization.yaml \
  /etc/genestack/kustomize/cert-manager/overlay/kustomization.yaml
```

If `/etc/genestack` is backed by an overrides repository, commit the equivalent
change there as well.

**RUN**: verify the kustomization file.

```bash
# RUN Verify cert-manager kustomization
cat /etc/genestack/kustomize/cert-manager/overlay/kustomization.yaml
```

Expected output:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../base
```

## Verify the Genestack cert-manager install script uses OCI

**RUN**: verify the install script chart source.

```bash
# RUN Verify cert-manager install script chart source
grep -E '^HELM_REPO' /opt/genestack/bin/install-cert-manager.sh
```

Expected output:

```text
HELM_REPO_NAME_DEFAULT="charts"
HELM_REPO_URL_DEFAULT="oci://quay.io/jetstack"
```

Bad output example:

```text
HELM_REPO_NAME_DEFAULT="cert-manager"
HELM_REPO_URL_DEFAULT="https://charts.jetstack.io"
```

If you see the bad output, stop and align `/opt/genestack` to the approved ref
before continuing. Do not locally edit this file as a substitute for using the
correct checkout.

**RUN**: verify no site override forces the old chart repository.

```bash
# RUN Check for site chart repository overrides
if [ -d /etc/genestack/helm-configs/cert-manager ]; then
  grep -R "repo_url\|repo_name\|service_name" /etc/genestack/helm-configs/cert-manager || true
else
  echo "No /etc/genestack/helm-configs/cert-manager directory found"
fi
```

Expected output on a simple environment:

```text
No /etc/genestack/helm-configs/cert-manager directory found
```

If a site override exists, ensure it does not point back to
`https://charts.jetstack.io` unless the environment has an explicit, documented
reason to use the legacy repository.

## Ensure kubespray will no longer install cert-manager

This maintenance converts _cert-manager_ to the Genestack chart-managed
installation path. _kubespray_ must not continue managing it.

**RUN**: verify `cert_manager_enabled` is false.

```bash
# RUN Verify kubespray no longer manages cert-manager
grep -n 'cert_manager_enabled' \
  /etc/genestack/inventory/group_vars/k8s_cluster/addons.yml
```

Expected output:

```text
12:cert_manager_enabled: false
```

If this is `true`, stop and make the applicable `/etc/genestack` or overrides
repository change before continuing.

## Verify the target chart version

**RUN**: verify both `(opt)` and `(etc)` target `v1.19.5`.

```bash
# RUN Verify cert-manager target version
grep -E '^[[:space:]]*cert-manager:' \
  /etc/genestack/helm-chart-versions.yaml \
  /opt/genestack/helm-chart-versions.yaml
```

Expected output:

```text
/etc/genestack/helm-chart-versions.yaml:  cert-manager: v1.19.5
/opt/genestack/helm-chart-versions.yaml:  cert-manager: v1.19.5
```

If `/opt/genestack/helm-chart-versions.yaml` does not show `v1.19.5`, stop and
align `/opt/genestack` to the approved ref.

If `/etc/genestack/helm-chart-versions.yaml` does not show `v1.19.5`, update
the site override and commit that change to the overrides repository if
applicable.

Example update command:

```bash
# RUN Update cert-manager target version in /etc if needed
sudo yq -i '.charts."cert-manager" = "v1.19.5"' \
  /etc/genestack/helm-chart-versions.yaml
```

## Verify base Genestack CA rotation policy

**RUN**: verify the Genestack base manifest explicitly preserves the public
endpoint CA private key.

```bash
# RUN Verify base rotation policy for public-endpoint-ca-cert
yq 'select(.metadata.name == "public-endpoint-ca-cert") | .spec.privateKey.rotationPolicy' \
  /opt/genestack/base-kustomize/envoyproxy-gateway/base/envoy-internal-gateway-issuer.yaml
```

Expected output:

```text
Never
```

Bad output example:

```text
null
```

If you see `null`, stop and align `/opt/genestack` to the approved ref before
continuing.

## Ensure cmctl exists

**RUN**: install `cmctl` if missing.

```bash
# RUN Ensure cmctl exists
source /opt/genestack/scripts/lib/functions.sh
ensureCmctl
cmctl version --client
```

Example output/expect:

```text
Client Version: util.Version{GitVersion:"v2.5.0", GitCommit:"46bd6766e7c7e345b29f1bc2dc737872bce6fb66", GitTreeState:"", GoVersion:"go1.26.2", Compiler:"gc", Platform:"linux/amd64"}
```

## Ensure Helm supports `--take-ownership`

**RUN**: verify the _Helm_ binary has the adoption flag.

```bash
# RUN Verify Helm supports --take-ownership
helm version --short
helm upgrade --help | grep -q -- '--take-ownership' || echo "Install Helm 3.17+"
```

Example good output:

```text
v3.21.0+ge0878d4
```

If the command prints `Install Helm 3.17+`, install an approved _Helm_ `3.x`
binary that contains `--take-ownership`. Genestack commonly uses a static
`/usr/local/bin/helm` binary.

**RUN**: optional _Helm_ `3.x` install example.

```bash
# RUN Install Helm 3.x example, if the current Helm lacks --take-ownership
helm version

sudo mv /usr/local/bin/helm /usr/local/bin/helm-$(helm version --template '{{ .Version }}')

cd /tmp
curl -fsSLO https://get.helm.sh/helm-v3.21.0-linux-amd64.tar.gz
curl -fsSLO https://get.helm.sh/helm-v3.21.0-linux-amd64.tar.gz.sha256sum
sha256sum -c helm-v3.21.0-linux-amd64.tar.gz.sha256sum

tar xzf helm-v3.21.0-linux-amd64.tar.gz
sudo install -o root -g root -m 0755 linux-amd64/helm /usr/local/bin/helm

helm version --short
helm upgrade --help | grep -q -- '--take-ownership' && echo "Helm supports --take-ownership"
```

Example output/expect:

```text
helm-v3.21.0-linux-amd64.tar.gz: OK
v3.21.0+ge0878d4
Helm supports --take-ownership
```

Use the approved version for the environment. The important requirement is
_Helm_ `3.17.x` or newer `3.x` with `--take-ownership`. Do not move to _Helm_
`4.x` for this maintenance unless Genestack has explicitly approved it.

## Verify support scripts exist

**RUN**: verify the cert-manager support scripts are present and executable.

```bash
# RUN Verify cert-manager support scripts
ls -l /opt/genestack/scripts/cert-manager-support/*.sh

test -x /opt/genestack/scripts/cert-manager-support/cert-manager-config-backup.sh
test -x /opt/genestack/scripts/cert-manager-support/cert-manager-upgrade-gate.sh
test -x /opt/genestack/scripts/cert-manager-support/show-issuers-and-solvers.sh
test -x /opt/genestack/scripts/cert-manager-support/show-certificates-and-issuers.sh
```

Example output/expect:

```text
rwxr-xr-x 1 ubuntu ubuntu  472 Jun  2 22:25 /opt/genestack/scripts/cert-manager-support/cert-manager-config-backup.sh
-rwxr-xr-x 1 ubuntu ubuntu 1077 Jun  2 22:26 /opt/genestack/scripts/cert-manager-support/cert-manager-upgrade-gate.sh
-rwxr-xr-x 1 ubuntu ubuntu  685 Jun  2 20:14 /opt/genestack/scripts/cert-manager-support/show-certificates-and-issuers.sh
-rwxr-xr-x 1 ubuntu ubuntu  478 Jun  2 20:15 /opt/genestack/scripts/cert-manager-support/show-issuers-and-solvers.sh
```

If the files are missing, stop and align `/opt/genestack` to the approved ref.

# Pre-Change Safety Checks

## Record issuers, certificates, and current Helm state

**RUN**: record a pre-change inventory.

```bash
# RUN Record pre-change cert-manager inventory
kubectl get issuer,clusterissuer,certificate,certificaterequest,order,challenge -A \
  -o wide > "$MAINT_DIR/cert-manager-prechange-crs.txt"

kubectl -n cert-manager get deployment,pods -o wide \
  > "$MAINT_DIR/cert-manager-prechange-workloads.txt"

helm -n cert-manager list --filter '^cert-manager$' \
  > "$MAINT_DIR/cert-manager-prechange-helm.txt"

ls -l "$MAINT_DIR"
```

Example output/expect:

```text
-rw-rw-r-- 1 ubuntu ubuntu  2480 Jun  3 18:40 cert-manager-prechange-crs.txt
-rw-rw-r-- 1 ubuntu ubuntu   642 Jun  3 18:40 cert-manager-prechange-helm.txt
-rw-rw-r-- 1 ubuntu ubuntu   927 Jun  3 18:40 cert-manager-prechange-workloads.txt
```

## Run the config backup script

The backup data is not used automatically by this runbook. It is collected so
that operators can inspect pre-change custom resources, secrets, and TLS
secrets if recovery work is needed.

Prefer forward repair over rollback if a later step fails.

**RUN**: back up cert-manager resources and TLS secrets.

```bash
# RUN Back up cert-manager config and TLS secrets
/opt/genestack/scripts/cert-manager-support/cert-manager-config-backup.sh
ls -l /home/ubuntu/cert-manager-backup
```

Example output/expect:

```text
total 432
-rw-rw-r-- 1 ubuntu ubuntu 280912 Jun  3 18:43 all-tls-secrets.yaml
-rw-rw-r-- 1 ubuntu ubuntu  30870 Jun  3 18:43 cert-manager-crs.yaml
-rw-rw-r-- 1 ubuntu ubuntu 126104 Jun  3 18:43 cert-manager-namespace-secrets.yaml
```

If these files are not created, stop and investigate before continuing.

## Run the upgrade gate as a baseline

Run the support gate before making changes. This establishes a baseline. If the
current environment is not yet Helm-managed, the Helm part of the output may be
missing or otherwise not meaningful before the takeover step. That is
acceptable only before the takeover step.

After the takeover step, the Helm release must exist and must match the
expected version.

Use the leading `v` in `EXPECTED_VERSION`.

**RUN**: pre-change gate.

```bash
# RUN Pre-change cert-manager gate
EXPECTED_VERSION=v1.15.3 \
  /opt/genestack/scripts/cert-manager-support/cert-manager-upgrade-gate.sh
```

Example output/expect when already Helm-managed:

```text
== cmctl API check ==
The cert-manager API is ready

== cert-manager version check ==
Helm release found. Checking Helm release version.
{
  "name": "cert-manager",
  "namespace": "cert-manager",
  "revision": "1",
  "status": "deployed",
  "chart": "cert-manager-v1.15.3",
  "app_version": "v1.15.3"
}
Helm release is deployed and matches expected version: v1.15.3

== Workload rollouts ==
Checking deployment.apps/cert-manager
deployment "cert-manager" successfully rolled out
Checking deployment.apps/cert-manager-cainjector
deployment "cert-manager-cainjector" successfully rolled out
Checking deployment.apps/cert-manager-webhook
deployment "cert-manager-webhook" successfully rolled out

All cert-manager upgrade gate checks passed
```

Example output/expect when not yet Helm-managed:

```text
== cmctl API check ==
The cert-manager API is ready

== cert-manager version check ==
No Helm release found. Checking cert-manager Deployment image tag.
cert-manager-controller image: quay.io/jetstack/cert-manager-controller:v1.15.3
Deployment image matches expected version: v1.15.3

== Workload rollouts ==
Checking deployment.apps/cert-manager
deployment "cert-manager" successfully rolled out
Checking deployment.apps/cert-manager-cainjector
deployment "cert-manager-cainjector" successfully rolled out
Checking deployment.apps/cert-manager-webhook
deployment "cert-manager-webhook" successfully rolled out

All cert-manager upgrade gate checks passed
```

Review the output. Do not rely only on the script exit code. A missing Helm JSON
object is acceptable only before takeover.

# Execute the Maintenance

## Dry-run the Helm takeover at v1.15.3

This dry-run verifies that the Genestack install script, chart source,
post-renderer, and local overrides are wired correctly before _Helm_ adopts the
existing resources.

**RUN**: dry-run the `v1.15.3` takeover.

```bash
# RUN Dry-run cert-manager v1.15.3 Helm takeover
cd /opt/genestack

bin/install-cert-manager.sh --dry-run --take-ownership \
  --version v1.15.3 \
  --set config.apiVersion=controller.config.cert-manager.io/v1alpha1 \
  --set config.kind=ControllerConfiguration | less
```

Expected:

- The command renders without error.
- The chart source is `oci://quay.io/jetstack/charts/cert-manager`.
- The _Helm_ command includes `--take-ownership`.
- The _Helm_ command includes the manual `--version v1.15.3` override.
- The post-renderer points at `/etc/genestack/kustomize/kustomize.sh` and the
  `cert-manager/overlay` argument.

Example output fragments:

```text
[DEBUG] HELM_REPO_NAME=charts
[DEBUG] SERVICE_NAME=cert-manager
[DEBUG] HELM_CHART_PATH=oci://quay.io/jetstack/charts/cert-manager
Including base overrides from directory: /opt/genestack/base-helm-configs/cert-manager
 - /opt/genestack/base-helm-configs/cert-manager/cert-manager-helm-overrides.yaml
Including overrides from service config directory: /etc/genestack/helm-configs/cert-manager

Executing Helm command (arguments are quoted safely):
... --version v1.15.3 ... --take-ownership
```

The script may print `Found version for cert-manager: v1.19.5` because the
version file already targets the final version. During the intermediate hops,
the explicit `--version` argument at the end of the command is intentional.

Resolve any dry-run errors before continuing.

## Adopt the existing install into Helm at v1.15.3

This step transfers ownership to the Genestack _Helm_ release while keeping the
application version at `v1.15.3`.

**RUN**: run the live `v1.15.3` takeover.

```bash
# RUN Adopt cert-manager into Helm at v1.15.3
cd /opt/genestack

bin/install-cert-manager.sh --take-ownership \
  --version v1.15.3 \
  --set config.apiVersion=controller.config.cert-manager.io/v1alpha1 \
  --set config.kind=ControllerConfiguration
```

Expected:

- _Helm_ succeeds.
- The release name is `cert-manager`.
- The namespace is `cert-manager`.
- The resulting chart/app version is `v1.15.3`.

## Post-check the v1.15.3 takeover

**RUN**: run the gate after takeover.

```bash
# RUN Post-check cert-manager v1.15.3 takeover
EXPECTED_VERSION=v1.15.3 \
  /opt/genestack/scripts/cert-manager-support/cert-manager-upgrade-gate.sh
```

Example output/expect:

```text
== cmctl API check ==
The cert-manager API is ready

== cert-manager version check ==
Helm release found. Checking Helm release version.
{
  "name": "cert-manager",
  "namespace": "cert-manager",
  "revision": "1",
  "status": "deployed",
  "chart": "cert-manager-v1.15.3",
  "app_version": "v1.15.3"
}
Helm release is deployed and matches expected version: v1.15.3

== Workload rollouts ==
Checking deployment.apps/cert-manager
deployment "cert-manager" successfully rolled out
Checking deployment.apps/cert-manager-cainjector
deployment "cert-manager-cainjector" successfully rolled out
Checking deployment.apps/cert-manager-webhook
deployment "cert-manager-webhook" successfully rolled out

All cert-manager upgrade gate checks passed
```

From this point forward, missing Helm release output is a failure. Resolve any
unexpected output before continuing.

## Upgrade to v1.16.5

**RUN**: upgrade to `v1.16.5`.

```bash
# RUN Upgrade cert-manager to v1.16.5
cd /opt/genestack
bin/install-cert-manager.sh --version v1.16.5
```

**RUN**: post-check `v1.16.5`.

```bash
# RUN Post-check cert-manager v1.16.5
EXPECTED_VERSION=v1.16.5 \
  /opt/genestack/scripts/cert-manager-support/cert-manager-upgrade-gate.sh
```

Example output/expect:

```text
== cmctl API check ==
The cert-manager API is ready

== cert-manager version check ==
Helm release found. Checking Helm release version.
{
  "name": "cert-manager",
  "namespace": "cert-manager",
  "revision": "2",
  "status": "deployed",
  "chart": "cert-manager-v1.16.5",
  "app_version": "v1.16.5"
}
Helm release is deployed and matches expected version: v1.16.5

== Workload rollouts ==
Checking deployment.apps/cert-manager
deployment "cert-manager" successfully rolled out
Checking deployment.apps/cert-manager-cainjector
deployment "cert-manager-cainjector" successfully rolled out
Checking deployment.apps/cert-manager-webhook
deployment "cert-manager-webhook" successfully rolled out

All cert-manager upgrade gate checks passed
```

Resolve or explain any unexpected new failure before continuing.

## Upgrade to v1.17.4

**RUN**: upgrade to `v1.17.4`.

```bash
# RUN Upgrade cert-manager to v1.17.4
cd /opt/genestack
bin/install-cert-manager.sh --version v1.17.4
```

**RUN**: post-check `v1.17.4`.

```bash
# RUN Post-check cert-manager v1.17.4
EXPECTED_VERSION=v1.17.4 \
  /opt/genestack/scripts/cert-manager-support/cert-manager-upgrade-gate.sh
```

Expected output is the same shape as the `v1.16.5` post-check, with:

```text
"chart": "cert-manager-v1.17.4",
"app_version": "v1.17.4"
```

Resolve or explain any unexpected new failure before continuing.

## Patch CA certificate rotation policy before v1.18.x

Patch live CA certificates before crossing the `v1.18.x` boundary. The most
important base Genestack certificate is `public-endpoint-ca-cert` in the
`cert-manager` namespace.

**RUN**: inspect the current live `public-endpoint-ca-cert` private key policy.

```bash
# RUN Inspect public-endpoint-ca-cert privateKey before v1.18.x
kubectl get certificate public-endpoint-ca-cert \
  -n cert-manager \
  -o yaml | yq '.spec.privateKey'
```

Example output before patching:

```yaml
algorithm: ECDSA
size: 256
```

Example output if already patched:

```yaml
algorithm: ECDSA
rotationPolicy: Never
size: 256
```

**RUN**: patch `public-endpoint-ca-cert` if `rotationPolicy: Never` is missing.

```bash
# RUN Patch public-endpoint-ca-cert to preserve CA private key
kubectl patch certificate public-endpoint-ca-cert \
  -n cert-manager \
  --type merge \
  -p '{"spec":{"privateKey":{"rotationPolicy":"Never"}}}'
```

Expected output:

```text
certificate.cert-manager.io/public-endpoint-ca-cert patched
```

If it already had the setting, output may be:

```text
certificate.cert-manager.io/public-endpoint-ca-cert patched (no change)
```

**RUN**: verify the live patch.

```bash
# RUN Verify public-endpoint-ca-cert privateKey after patch
kubectl get certificate public-endpoint-ca-cert \
  -n cert-manager \
  -o yaml | yq '.spec.privateKey'
```

Expected output:

```yaml
algorithm: ECDSA
rotationPolicy: Never
size: 256
```

**RUN**: check for additional CA certificates.

```bash
# RUN Find additional CA certificates
kubectl get certificates -A -o json | jq -r '
  ["NAMESPACE","NAME","IS_CA","SECRET","ROTATION_POLICY"],
  (.items[]
  | select(.spec.isCA == true)
  | [
      .metadata.namespace,
      .metadata.name,
      (.spec.isCA // false),
      (.spec.secretName // ""),
      (.spec.privateKey.rotationPolicy // "<unset>")
    ])
  | @tsv' | column -t -s $'\t'
```

Example output/expect:

```text
NAMESPACE     NAME                    IS_CA  SECRET                     ROTATION_POLICY
cert-manager  public-endpoint-ca-cert true   public-endpoint-ca-secret  Never
```

If the environment has additional CA certificates, decide whether those CA
private keys must also be preserved. Patch only certificates where preserving
the CA private key is operationally required.

## Upgrade to v1.18.6

**RUN**: upgrade to `v1.18.6`.

```bash
# RUN Upgrade cert-manager to v1.18.6
cd /opt/genestack
bin/install-cert-manager.sh --version v1.18.6
```

The chart notes may include a warning similar to this:

```text
WARNING: New default private key rotation policy for Certificate resources.
The default private key rotation policy for Certificate resources was changed.
```

This runbook accounts for that change by explicitly setting
`rotationPolicy: Never` on Genestack CA certificates that must preserve their
private keys.

**RUN**: post-check `v1.18.6`.

```bash
# RUN Post-check cert-manager v1.18.6
EXPECTED_VERSION=v1.18.6 \
  /opt/genestack/scripts/cert-manager-support/cert-manager-upgrade-gate.sh
```

Expected output is the same shape as previous post-checks, with:

```text
"chart": "cert-manager-v1.18.6",
"app_version": "v1.18.6"
```

Resolve or explain any unexpected new failure before continuing.

## Upgrade to v1.19.5

The target version should now come from `/etc/genestack/helm-chart-versions.yaml`
and `/opt/genestack/helm-chart-versions.yaml`. Do not pass an explicit
`--version` on the final step unless you are deliberately overriding the site
version file.

**RUN**: install the target `v1.19.5` version.

```bash
# RUN Upgrade cert-manager to v1.19.5
cd /opt/genestack
bin/install-cert-manager.sh
```

**RUN**: post-check `v1.19.5`.

```bash
# RUN Post-check cert-manager v1.19.5
EXPECTED_VERSION=v1.19.5 \
  /opt/genestack/scripts/cert-manager-support/cert-manager-upgrade-gate.sh
```

Example output/expect:

```text
== cmctl API check ==
The cert-manager API is ready

== cert-manager version check ==
Helm release found. Checking Helm release version.
{
  "name": "cert-manager",
  "namespace": "cert-manager",
  "revision": "5",
  "status": "deployed",
  "chart": "cert-manager-v1.19.5",
  "app_version": "v1.19.5"
}
Helm release is deployed and matches expected version: v1.19.5

== Workload rollouts ==
Checking deployment.apps/cert-manager
deployment "cert-manager" successfully rolled out
Checking deployment.apps/cert-manager-cainjector
deployment "cert-manager-cainjector" successfully rolled out
Checking deployment.apps/cert-manager-webhook
deployment "cert-manager-webhook" successfully rolled out

All cert-manager upgrade gate checks passed
```

## Verify CA rotation policy after final upgrade

**RUN**: verify `public-endpoint-ca-cert` still preserves the CA private key.

```bash
# RUN Verify public-endpoint-ca-cert after final upgrade
kubectl get certificate public-endpoint-ca-cert \
  -n cert-manager \
  -o yaml | yq '.spec.privateKey'
```

Expected output:

```yaml
algorithm: ECDSA
rotationPolicy: Never
size: 256
```

If `rotationPolicy` is missing, patch it again and investigate why the live
resource diverged from the expected base configuration.

# Post-Maint

## Verify final workload and release state

**RUN**: verify final _Helm_ and workload state.

```bash
# RUN Verify final cert-manager release and workloads
helm -n cert-manager list --filter '^cert-manager$'
kubectl -n cert-manager get deployment,pods
cmctl check api --wait=2m
```

Example output/expect:

```text
NAME            NAMESPACE       REVISION        UPDATED                                 STATUS          CHART                   APP VERSION
cert-manager    cert-manager    5               2026-06-03 18:07:13.923625959 +0000 UTC deployed        cert-manager-v1.19.5    v1.19.5

NAME                                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/cert-manager              1/1     1            1           5d21h
deployment.apps/cert-manager-cainjector   1/1     1            1           5d21h
deployment.apps/cert-manager-webhook      1/1     1            1           5d21h

NAME                                           READY   STATUS    RESTARTS   AGE
pod/cert-manager-88878f695-p24fx               1/1     Running   0          109s
pod/cert-manager-cainjector-795b77546c-48cfr   1/1     Running   0          109s
pod/cert-manager-webhook-84f74d8b9d-dxfjm      1/1     Running   0          109s

The cert-manager API is ready
```

## Verify issuers and solvers

**RUN**: show ClusterIssuers and solver mechanisms.

```bash
# RUN Show issuers and solvers
/opt/genestack/scripts/cert-manager-support/show-issuers-and-solvers.sh
```

Example output/expect for a default HTTP01 environment:

```text
letsencrypt-prod           HTTP01  gatewayHTTPRoute
letsencrypt-prod-internal  HTTP01  gatewayHTTPRoute
```

If the environment has DNS01 and HTTP01, test at least one low-risk certificate
for each solver mechanism when practical.

## Choose a certificate renewal test target

Avoid repeatedly renewing the same public Let's Encrypt certificate. Let's
Encrypt limits issuance for the exact same set of identifiers. Select a
low-risk certificate and do not select a wildcard certificate merely for this
maintenance test.

For most default Genestack installations, one low-risk HTTP01 certificate is
sufficient because both shown issuers use the same HTTP01 solver mechanism. If
the environment has multiple solver mechanisms, choose one low-risk certificate
for each mechanism you intend to validate.

**RUN**: list certificates and issuers.

```bash
# RUN List certificates and their issuers
/opt/genestack/scripts/cert-manager-support/show-certificates-and-issuers.sh
```

Example output/expect:

```text
NAMESPACE      NAME                          READY  ISSUER                     DNS_NAMES
envoy-gateway  barbican-gw-tls-secret        True   letsencrypt-prod           barbican.api.dev.dfw3.rackspacecloud.com
envoy-gateway  blazar-gw-tls-secret          True   letsencrypt-prod           blazar.api.dev.dfw3.rackspacecloud.com
envoy-gateway  cinder-gw-tls-secret          True   letsencrypt-prod           cinder.api.dev.dfw3.rackspacecloud.com
envoy-gateway  glance-gw-tls-secret          True   letsencrypt-prod           glance.api.dev.dfw3.rackspacecloud.com
envoy-gateway  keystone-gw-tls-secret        True   letsencrypt-prod           keystone.api.dev.dfw3.rackspacecloud.com
envoy-gateway  nova-gw-tls-secret            True   letsencrypt-prod           nova.api.dev.dfw3.rackspacecloud.com
envoy-gateway  wildcard-cluster-tls-secret   False  letsencrypt-prod           *.cluster.local
rackspace      alertmanager-gw-tls-secret    True   letsencrypt-prod-internal  alertmanager.dev.dfw.ohthree.com
rackspace      grafana-gw-tls-secret         True   letsencrypt-prod-internal  grafana.dev.dfw.ohthree.com
rackspace      longhorn-gw-tls-secret        True   letsencrypt-prod-internal  longhorn.dev.dfw.ohthree.com
rackspace      prometheus-gw-tls-secret       True   letsencrypt-prod-internal  prometheus.dev.dfw.ohthree.com
rackspace      rabbitmq-gw-tls-secret        True   letsencrypt-prod-internal  mq.dev.dfw.ohthree.com
```

If the environment has a fronting WAF, CDN, or wildcard certificate outside the
cluster, the certificate served by the public URL may not match the certificate
stored in the cluster. For this maintenance, validate the certificate object and
secret managed by _cert-manager_ inside the cluster.

## Renew one low-risk certificate

This example uses `rackspace/alertmanager-gw-tls-secret`. Replace it with the
certificate selected for the environment.

**RUN**: show the selected certificate before renewal.

```bash
# RUN Show selected certificate before renewal
cmctl status certificate -n rackspace alertmanager-gw-tls-secret
```

Example output/expect:

```text
Name: alertmanager-gw-tls-secret
Namespace: rackspace
Created at: 2026-05-07T14:25:54Z
Conditions:
  Ready: True, Reason: Ready, Message: Certificate is up to date and has not expired
DNS Names:
- alertmanager.dev.dfw.ohthree.com
Events:  <none>
Issuer:
  Name: letsencrypt-prod-internal
  Kind: ClusterIssuer
  Conditions:
    Ready: True, Reason: ACMEAccountRegistered, Message: The ACME account was registered with the ACME server
Secret:
  Name: alertmanager-gw-tls-secret
  Issuer Organisation: Let's Encrypt
  Issuer Common Name: YR1
  Public Key Algorithm: RSA
  Signature Algorithm: SHA256-RSA
  Serial Number: 060420f5f9af91233f9b0e7457dac46e36f3
Not Before: 2026-05-29T20:46:08Z
Not After: 2026-08-27T20:46:07Z
Renewal Time: 2026-07-28T20:46:07Z
```

**RUN**: renew the selected certificate.

```bash
# RUN Trigger renewal for selected certificate
cmctl renew --namespace rackspace alertmanager-gw-tls-secret
```

Expected output:

```text
Manually triggered issuance of Certificate rackspace/alertmanager-gw-tls-secret
```

Renewal runs asynchronously. Check the status again after a short interval. If
the status has not changed yet, re-run the status command a few times.

**RUN**: show the selected certificate after renewal.

```bash
# RUN Show selected certificate after renewal
cmctl status certificate -n rackspace alertmanager-gw-tls-secret
```

Example output/expect after successful renewal:

```text
Name: alertmanager-gw-tls-secret
Namespace: rackspace
Created at: 2026-05-07T14:25:54Z
Conditions:
  Ready: True, Reason: Ready, Message: Certificate is up to date and has not expired
DNS Names:
- alertmanager.dev.dfw.ohthree.com
Events:
  Type    Reason     Age   From                                       Message
  ----    ------     ----  ----                                       -------
  Normal  Generated  67s   cert-manager-certificates-key-manager      Stored new private key in temporary Secret resource "alertmanager-gw-tls-secret-rxzwx"
  Normal  Requested  67s   cert-manager-certificates-request-manager  Created new CertificateRequest resource "alertmanager-gw-tls-secret-4"
  Normal  Issuing    65s   cert-manager-certificates-issuing          The certificate has been successfully issued
Issuer:
  Name: letsencrypt-prod-internal
  Kind: ClusterIssuer
  Conditions:
    Ready: True, Reason: ACMEAccountRegistered, Message: The ACME account was registered with the ACME server
Secret:
  Name: alertmanager-gw-tls-secret
  Issuer Organisation: Let's Encrypt
  Issuer Common Name: YR2
  Public Key Algorithm: RSA
  Signature Algorithm: SHA256-RSA
  Serial Number: 0518d5ffb2faf0fd195439e13cedee241570
Not Before: 2026-06-01T19:37:34Z
Not After: 2026-08-30T19:37:33Z
Renewal Time: 2026-07-31T19:37:33Z
```

The important checks are:

- `Ready: True`
- a new `CertificateRequest` was created
- `The certificate has been successfully issued`
- `Not Before`, `Not After`, or `Serial Number` changed

## Check Orders and Challenges if renewal did not complete

**RUN**: inspect recent _cert-manager_ ACME resources.

```bash
# RUN Inspect orders and challenges if renewal failed or stalled
kubectl get certificaterequest,order,challenge -A --sort-by=.metadata.creationTimestamp | tail -n 30
```

**RUN**: describe the newest relevant resource.

```bash
# RUN Describe the relevant failed challenge or order
kubectl -n <namespace> describe challenge <challenge-name>
kubectl -n <namespace> describe order <order-name>
```

Resolve DNS, HTTPRoute, Gateway, or ACME account issues before declaring the
maintenance complete.

# Troubleshooting

## Helm takeover fails with existing resource ownership errors

Confirm the _Helm_ binary supports `--take-ownership` and confirm the live
command included that flag.

```bash
helm version --short
helm upgrade --help | grep -- '--take-ownership'
```

Re-run the `v1.15.3` takeover command only after the flag is confirmed.

## Post-renderer or kustomize errors

Check the cert-manager kustomize directory and the Genestack kustomize wrapper.

```bash
ls -lR /etc/genestack/kustomize/cert-manager
cat /etc/genestack/kustomize/cert-manager/overlay/kustomization.yaml
test -x /etc/genestack/kustomize/kustomize.sh
```

The minimal overlay should contain only:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../base
```

## cmctl API check fails

Check workloads, webhook service endpoints, and logs.

```bash
kubectl -n cert-manager get deployment,pods,svc,endpoints
kubectl -n cert-manager logs deployment/cert-manager --tail=100
kubectl -n cert-manager logs deployment/cert-manager-webhook --tail=100
kubectl -n cert-manager logs deployment/cert-manager-cainjector --tail=100
kubectl get apiservice | grep cert-manager || true
```

Restore the API before continuing to the next version hop.

## Helm reports the wrong chart or app version

Check the final _Helm_ arguments and verify that `EXPECTED_VERSION` includes
the leading `v`.

```bash
helm -n cert-manager list --filter '^cert-manager$' -o json \
  | jq -r '.[] | {name, namespace, revision, status, chart, app_version}'
```

Expected final values:

```text
"chart": "cert-manager-v1.19.5"
"app_version": "v1.19.5"
```

## public-endpoint-ca-cert rotationPolicy is missing after upgrade

Patch it back to `Never` and inspect how the resource is being managed.

```bash
kubectl patch certificate public-endpoint-ca-cert \
  -n cert-manager \
  --type merge \
  -p '{"spec":{"privateKey":{"rotationPolicy":"Never"}}}'

kubectl get certificate public-endpoint-ca-cert \
  -n cert-manager \
  -o yaml | yq '.spec.privateKey'
```

Also verify the base Genestack manifest still contains `rotationPolicy: Never`:

```bash
yq 'select(.metadata.name == "public-endpoint-ca-cert") | .spec.privateKey.rotationPolicy' \
  /opt/genestack/base-kustomize/envoyproxy-gateway/base/envoy-internal-gateway-issuer.yaml
```

## ACME renewal fails

Inspect the selected certificate, certificate request, order, challenge, and
issuer.

```bash
cmctl status certificate -n <namespace> <certificate-name>
kubectl -n <namespace> get certificaterequest,order,challenge
kubectl -n <namespace> describe certificaterequest <certificate-request-name>
kubectl -n <namespace> describe order <order-name>
kubectl -n <namespace> describe challenge <challenge-name>
kubectl get clusterissuer <issuer-name> -o yaml
```

For HTTP01 Gateway API challenges, also inspect the relevant routes and gateway
objects.

```bash
kubectl get gateway,httproute -A | grep -i acme || true
kubectl get events -A --sort-by='.lastTimestamp' | tail -n 100
```

# Rollback and recovery posture

Rollback is not the primary recovery path for this maintenance. Prefer restoring
forward progress by fixing the failed version hop and continuing to `v1.19.5`.

Do not re-enable _kubespray_ management of _cert-manager_ during recovery unless
there is a separate, reviewed recovery plan. Re-enabling _kubespray_ after
_Helm_ adoption can reintroduce ownership conflict.

Do not uninstall _cert-manager_ to recover from a failed step unless a separate
rebuild plan has been reviewed. Uninstall and reinstall changes the failure mode
from an upgrade problem to a certificate control-plane rebuild problem.

If a _Helm_ rollback is chosen after the takeover has succeeded, roll back only
to a known-good _Helm_ revision and immediately run the gate again.

```bash
helm -n cert-manager history cert-manager
helm -n cert-manager rollback cert-manager <known-good-revision>

EXPECTED_VERSION=<known-good-version-with-leading-v> \
  /opt/genestack/scripts/cert-manager-support/cert-manager-upgrade-gate.sh
```

Example:

```bash
helm -n cert-manager rollback cert-manager 4

EXPECTED_VERSION=v1.18.6 \
  /opt/genestack/scripts/cert-manager-support/cert-manager-upgrade-gate.sh
```

After any rollback, verify `public-endpoint-ca-cert` still has:

```yaml
rotationPolicy: Never
```

# Final acceptance criteria

The maintenance is complete when all of the following are true:

- `/etc/genestack/inventory/group_vars/k8s_cluster/addons.yml` has
  `cert_manager_enabled: false`.
- `/etc/genestack/kustomize/cert-manager/overlay/kustomization.yaml` exists and
  references `../base`.
- `/etc/genestack/helm-chart-versions.yaml` targets `cert-manager: v1.19.5`.
- `/opt/genestack/bin/install-cert-manager.sh` uses the OCI chart source.
- `helm -n cert-manager list --filter '^cert-manager$'` shows
  `cert-manager-v1.19.5` and `STATUS` `deployed`.
- `cmctl check api --wait=2m` reports the API is ready.
- `cert-manager`, `cert-manager-cainjector`, and `cert-manager-webhook`
  deployments are successfully rolled out.
- `public-endpoint-ca-cert` has `rotationPolicy: Never`.
- At least one selected low-risk certificate renewal was successfully tested, or
  a documented reason exists for not performing a public ACME renewal test.

# References

These references explain the version and behavior assumptions behind the
runbook. They are not command inputs.

- cert-manager upgrade guidance:
  https://cert-manager.io/docs/installation/upgrade/
- cert-manager v1.17 to v1.18 upgrade notes:
  https://cert-manager.io/docs/releases/upgrading/upgrading-1.17-1.18/
- cert-manager Helm install guidance:
  https://cert-manager.io/docs/installation/helm/
- Helm v3.17.0 release notes for `--take-ownership`:
  https://github.com/helm/helm/releases/tag/v3.17.0
- Let's Encrypt rate limits:
  https://letsencrypt.org/docs/rate-limits/
