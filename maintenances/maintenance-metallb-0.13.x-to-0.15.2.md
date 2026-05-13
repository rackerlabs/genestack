# Component Maintenance: MetalLB `0.13.x` to `0.15.2`

# Notes

(opt) refers to /opt, the standard install path for _Genestack_.
(etc) refers to /etc, the standard override path for _Genestack_.

This runbook upgrades _MetalLB_ first, then replaces deprecated
_Service_ annotations using the `metallb.universe.tf` prefix with the
supported `metallb.io` prefix on affected _Services_ and related
manifests.

Do not replace live _Service_ annotations with `metallb.io` until after
_MetalLB_ `0.15.2` is running. The old version does not support the new
annotations, but the new version does accept the deprecated annotation,
so this ensures maximum availability.

Save the deprecated annotation inventory before making changes. That
inventory includes the _namespace_, _kind_, _Service_ name, and the
deprecated annotation key and value. Use that saved data to create the
new `metallb.io` annotation with the exact same value, then remove the
deprecated `metallb.universe.tf` key.

Ignore `metallb.universe.tf/ip-allocated-from-pool` in annotation
checks. (Equivalently, you should ignore
`metallb.io/ip-allocated-from-pool`, as they replaced
`metallb.universe.tf` with `metallb.io` wholesale without "schema" type
changes at all.) _MetalLB_ manages that annotation automatically and the
old key can linger or get after upgrades, which seems due to a _MetalLB_
bug.

# Validation

- Validated source version: _MetalLB_ `0.13.9` through `0.13.12`
- Validated target version: _MetalLB_ `0.15.2`
- Validated platform dependency:
    - Genestack deployment using `/opt/genestack` and `/etc/genestack`
    - _MetalLB_ may already be _Helm_-managed, or may still have legacy
      non-_Helm_ resources from an earlier _kubespray_ or other install
      path

# Supported upgrade path

- Direct upgrade from MetalLB `0.13.9` through `0.13.12` to `0.15.2`
- No `0.14.x` intermediate hop is required for this runbook

# Major operational risks for this maintenance

* brief interruption of `LoadBalancer` service reconciliation while
  _MetalLB_ restarts

* dependent components may continue recreating deprecated
  `metallb.universe.tf` annotations until manifests or overrides are
  corrected and the components are redeployed

* _MariaDB_ and _RabbitMQ_ pod restarts may affect control-plane APIs
  during the maintenance window

* legacy non-_Helm_ _MetalLB_ resources can block a _Helm_-managed
  install

* _Helm_ rollback is only practical in previously _Helm_-managed
  environments and requires restoration of the old
  `metallb.universe.tf` annotations for `0.13.x` behavior

# Goal

Upgrade _MetalLB_ from `0.13.x` to `0.15.2` without service regression,
redeploy affected components that manage `LoadBalancer` _Services_,
replace non-ignored `metallb.universe.tf` annotations with metallb.io
annotations using the same values, and leave all affected workloads
healthy and externally reachable.

# Prep

## Deployment Node

Use the _Genestack_ deployment host or bastion that has:

* `kubectl` access to the target cluster
* `helm`, `jq`, `yq`, `grep`, `sed`
* `/opt/genestack` checked out to the target _Genestack_ release
* `/etc/genestack` populated for the target site

**RUN**: Create a working directory for this maintenance:

```bash
# RUN Create a working directory for this maintenance
export MAINT_DIR=/home/ubuntu/metallb-0.15.2-maint
mkdir -p "$MAINT_DIR"
```

## Verify current component health

**RUN**: verify current component health

```bash
# RUN Verify current component health
kubectl -n metallb-system get deployment,daemonset,pods
```

Example output/expect:

```
NAME                         READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/controller   1/1     1            1           2m19s

NAME                     DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR            AGE
daemonset.apps/speaker   3         3         3       3            3           kubernetes.io/os=linux   2m19s

NAME                              READY   STATUS    RESTARTS       AGE
pod/controller-576fddb64d-sbhbt   1/1     Running   1 (108s ago)   2m19s
pod/speaker-hcrhz                 1/1     Running   0              2m19s
pod/speaker-sjrkp                 1/1     Running   0              2m19s
pod/speaker-t9n9k                 1/1     Running   0              2m19s
```

- Restore health if components look unhealthy.

**RUN**: to check _MariaDB_

```
# RUN to check MariaDB
kubectl -n mariadb-system get pods || true
```

Example output/expect:

```
NAME                                        READY   STATUS    RESTARTS        AGE
mariadb-operator-896f9f644-6hgwl            1/1     Running   2 (3h11m ago)   3h11m
mariadb-operator-896f9f644-7kdr2            1/1     Running   2 (3h11m ago)   3h11m
mariadb-operator-896f9f644-vjbds            1/1     Running   2 (3h11m ago)   3h11m
mariadb-operator-webhook-5448b4f575-65fbj   1/1     Running   0               3h11m
mariadb-operator-webhook-5448b4f575-dzgs6   1/1     Running   0               3h11m
mariadb-operator-webhook-5448b4f575-n2j2c   1/1     Running   0               3h11m
```

Restore health if components look unhealthy.

**RUN**: to check `mariadb`s + `rabbitmqclusters`

```bash
# RUN
kubectl -n openstack get mariadb,rabbitmqclusters.rabbitmq.com || true
```

Example output/expect:

```
NAME                                      READY   STATUS    PRIMARY             UPDATES         AGE
mariadb.k8s.mariadb.com/mariadb-cluster   True    Running   mariadb-cluster-0   RollingUpdate   3h11m

NAME                                    ALLREPLICASREADY   RECONCILESUCCESS   AGE
rabbitmqcluster.rabbitmq.com/rabbitmq   True               True               3h11m
```

- Restore health if components look unhealthy.

**RUN**: to check _Grafana_

```
# RUN
kubectl get pods -A | grep grafana || true
```

example output/expect:

```
monitoring                  grafana-66588757bc-xhc24                                          1/1     Running     2 (13d ago)     13d
```

- Restore health if components look unhealthy.

**RUN**: to check Namespace `envoy-gateway-system` resources

```
# RUN
kubectl -n envoyproxy-gateway-system get deployment,pods || true
```

Example output/expect:

```
NAME                                                        READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/envoy-envoy-gateway-flex-gateway-e868ef77   2/2     2            2           22d
deployment.apps/envoy-gateway                               1/1     1            1           22d
deployment.apps/envoy-rackspace-flex-rax-gateway-3b619720   2/2     2            2           22d

NAME                                                             READY   STATUS    RESTARTS   AGE
pod/envoy-envoy-gateway-flex-gateway-e868ef77-56984cbbfc-ftvkw   2/2     Running   0          13d
pod/envoy-envoy-gateway-flex-gateway-e868ef77-56984cbbfc-rwfsx   2/2     Running   0          13d
pod/envoy-gateway-66d489cccd-9zgcw                               1/1     Running   0          13d
pod/envoy-rackspace-flex-rax-gateway-3b619720-975755c7d-frph8    2/2     Running   0          13d
pod/envoy-rackspace-flex-rax-gateway-3b619720-975755c7d-thr6w    2/2     Running   0          13d
```

Restore health if components look unhealthy.


## Verify current cluster or platform health

**RUN**: to verify current cluster or platform health

```
# RUN
kubectl get nodes
```

Example output/expect:

```
NAME                                         STATUS   ROLES                  AGE     VERSION
hyperconverged-metallb-033-0.cluster.local   Ready    control-plane,worker   3h33m   v1.33.5
hyperconverged-metallb-033-1.cluster.local   Ready    control-plane,worker   3h32m   v1.33.5
hyperconverged-metallb-033-2.cluster.local   Ready    control-plane,worker   3h32m   v1.33.5
```

- Restore health if components look unhealthy. Note bad nodes, etc. for
  later steps.

**RUN**: to check for pods in bad states

```
# RUN
kubectl get pods -A --no-headers | awk '$4 != "Running" && $4 != "Completed" {print}'
```

Example output/expect:

- List of pods in status other than running or completed.
- Resolve any issues and continue.

**RUN**: to check if _MetalLB_ installed via chart and chart status

```
# RUN to check if MetalLB via chart and chart status
helm -n metallb-system list
```

Example output/expect:

- _Helm_ release may or may not exist, depending on environment
- Some older environments may not have MetalLB installed from chart:

    ```
    NAME	NAMESPACE	REVISION	UPDATED	STATUS	CHART	APP VERSION
    ```

- Newer environments may have installed from chart:

    ```
    NAME   	NAMESPACE     	REVISION	UPDATED                                STATUS  	CHART         	APP VERSION
    metallb	metallb-system	1       	2026-04-07 21:48:23.025233445 +0000 UTCdeployed	metallb-0.15.2	v0.15.2
    ```

- Note carefully here if you start with `0.13.x`, as we primarily
  validated going `v0.13.x` to `v0.15.2` directly
- Note carefully also whether you installed from chart, you will use
  this information later.

**RUN**: to check _MetalLB_ deployment health

```
# RUN
kubectl -n metallb-system get deployment controller \
-o jsonpath='{range .spec.template.spec.containers[*]}{.image}{"\n"}{end}'
```

Example output/expect:

```
quay.io/metallb/controller:v0.13.9
```

- This helps verify version on environments with _MetalLB_ installed via
  _kubespray_ and not via chart.
- As above, note that version shows `v0.13.x` as we validated going
  `v0.13.x` to `v0.15.2` via clean installation.
- the controller image tag is in the `0.13.9` through `0.13.12` range
- If the current version does not match MetalLB `0.13.9` through
  `0.13.12`, stop and reassess.

## Verify backups, snapshots, or restore points are available

**RUN**: to verify backups, snapshots, or restore points are available

```
# RUN
if [[ -n "$MAINT_DIR" ]]
then
  kubectl get ipaddresspools,l2advertisements -n metallb-system -o yaml > "$MAINT_DIR/metallb-l2-config.yaml"
  kubectl get all -n metallb-system -o yaml > "$MAINT_DIR/metallb-runtime-backup.yaml"
  kubectl get sa,role,rolebinding,clusterrole,clusterrolebinding -n metallb-system -o yaml > "$MAINT_DIR/metallb-rbac-backup.yaml"

  kubectl get mariadb mariadb-cluster -n openstack -o jsonpath='{.spec.replicas}{"\n"}' > "$MAINT_DIR/mariadb-original-replicas.txt" || true
  ls $MAINT_DIR
else
  echo "This step requires MAINT_DIR set as further up in the directions"
fi
```

Output/expect backup files as shown from the ls:

```
mariadb-original-replicas.txt  metallb-rbac-backup.yaml
metallb-l2-config.yaml         metallb-runtime-backup.yaml
```

**RUN**: to backup MariaDB:

```
# RUN
MARIADB_ROOT_PASSWORD="$(kubectl -n openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)"
kubectl exec -i $(kubectl get mariadb mariadb-cluster -n openstack -o jsonpath="{.status.currentPrimary}") -n openstack -- mariadb-dump \
  -u root -p"$MARIADB_ROOT_PASSWORD" \
  --all-databases \
  --single-transaction \
  --routines \
  --triggers > $MAINT_DIR/mariadb-cluster-full-backup-$(date +%Y%m%d-%H%M).sql
ls -l $MAINT_DIR/mariadb-cluster-full-backup-*.sql
```

Output/expect:

- Expect to see the completed dump file with non-zero size:

```
-rw-rw-r-- 1 ubuntu ubuntu 3965340 Apr 30 19:22 /home/ubuntu/metallb-0.15.2-maint/mariadb-cluster-full-backup-20260430-1922.sql
```

# Configuration Review

**RUN**: to verify the current config:

```
# Run
grep '^[[:space:]]*metallb:' /etc/genestack/helm-chart-versions.yaml
grep -R "metallb.universe.tf/" /opt/genestack/base-kustomize || true
grep -R "metallb.universe.tf/" /etc/genestack/helm-configs /etc/genestack/kustomize || true
```

Output/expect:

```
  metallb: v0.15.2
```

- You *shouldn't* get `metallb.universe.tf`, output. Check your commit
  if any of that exists.
- `/etc/genestack/helm-chart-versions.yaml` contains `metallb: v0.15.2`
  before the install step
- `/opt/genestack/base-kustomize` should not contain `metallb.universe.tf`
  references on the target _Genestack_ release
- any site-specific matches under `/etc/genestack` must reflect
  with `metallb.io` before dependent components are redeployed

# Pre-Change Safety Checks

Check for open alerts or issues:

**RUN**: to check for open alerts or issues:

```bash
# RUN
kubectl get events -A --sort-by='.lastTimestamp' | tail -n 100
```

Output/expect:

- Awareness only, no known, noted, or particular expected issues to
  check for.
- Look at the output and see if anything seems concerning for your
  cluster/deployment.

**RUN**: to verify the version source of truth:

```
# RUN
grep '^[[:space:]]*metallb:' /etc/genestack/helm-chart-versions.yaml
```

Output/expect:

```
  metallb: v0.15.2
```

- This upgrade targets _MetalLB_ `0.15.2`. Verify the commit for your
  site or installation overrides if you don't see this.

# Apply Required Overrides or Patches

Review for site-specific overrides or custom manifests that still
reference `metallb.universe.tf`:

**RUN** to review for site-specific overrides or custom manifests that still
reference `metallb.universe.tf`:

```bash
# RUN
grep -R "metallb.universe.tf/" \
/etc/genestack/helm-configs /etc/genestack/kustomize || true
```

Expect:

```
```

- Expect no output
- You should get no lines generally, especially lines containing the
  deprecated annotations.
- Re-check the commit for your workdir and that you have followed
  previous steps if you see any. You should not have these at this
  point.


**RUN**

```
# RUN
helm -n metallb-system list
```

Expect:

- Possibly no output, as many environments will have had
  `metallb-system` installed via kubespray.
- Possibly the output listing an installed chart.
- **Make a note if you have this installed by chart, we will uninstall
  it shortly.**

**RUN**:

```
# RUN
kubectl get validatingwebhookconfiguration,\
mutatingwebhookconfiguration | grep metallb || true
kubectl get clusterrole,clusterrolebinding | grep metallb-system || \
true
```

Output/expect:

```
validatingwebhookconfiguration.admissionregistration.k8s.io/metallb-webhook-configuration     7          113m
clusterrole.rbac.authorization.k8s.io/metallb-system:controller                                              2026-04-30T17:56:03Z
clusterrole.rbac.authorization.k8s.io/metallb-system:speaker                                                 2026-04-30T17:56:03Z
clusterrolebinding.rbac.authorization.k8s.io/metallb-system:controller                                           ClusterRole/metallb-system:controller                                              113m
clusterrolebinding.rbac.authorization.k8s.io/metallb-system:speaker                                              ClusterRole/metallb-system:speaker                                                 113m
```

- We remove this stuff later.

# Execute the Maintenance

Verify MetalLB works before proceeding:

**RUN**: *EXTERNALLY*/from your laptop/workstation

```
env OS_CLOUD=<this enviroment> openstack token issue
```

output/Expect:

```
+------------+-----------------------------------------------------------------+
| Field      | Value                                                           |
+------------+-----------------------------------------------------------------+
| expires    | 2026-05-01T07:54:26+0000                                        |
| id         | REDACTEDREDACTEDREDACTEDgxMxuX9IvYRcMZS4MdRGVjYE45a5UHtEF-scxau |
|            | eYIiG07AjqZON5l-                                               |
|            | _knYOmy1G4S_4npLnWlxMNmjvsKNV1ZbrzBDgIAbGaSNEqXHStMl40JXKpLV03h |
|            | sf1EovzCaWQz__lHLc7gGroEW_Byg2ugaw4Ni6q2erf5KRs8gAjshY7meItMUF8 |
|            | zDPe70SiYuH8k17QtavTnPx3dgACnpUGEGU1eZoI3PCwmIElTXXXr3C1ZacA2XL |
| project_id | af738c5722e995b96f331c1ccd542275                                |
| user_id    | 6f2f19bd5ac1754a029d8fa3a73b4a0dcceff61a8407a9b8078cf288be786ad |
|            | c                                                               |
+------------+-----------------------------------------------------------------+
```

- This should work at this point and verifies you had working metalLB,
  and we will postcheck like this.

Stage 1: Upgrade MetalLB

**RUN**: **ONLY IF NOT INSTALLED BY CHART**

```
# RUN IF NOT INSTALLED VIA CHART
kubectl delete validatingwebhookconfiguration metallb-webhook-configuration --ignore-not-found
kubectl delete mutatingwebhookconfiguration metallb-webhook-configuration --ignore-not-found
kubectl delete clusterrole metallb-system:controller metallb-system:speaker --ignore-not-found
kubectl delete clusterrolebinding metallb-system:controller metallb-system:speaker --ignore-not-found
kubectl delete crd \
  addresspools.metallb.io \
  bfdprofiles.metallb.io \
  bgpadvertisements.metallb.io \
  bgppeers.metallb.io \
  communities.metallb.io \
  ipaddresspools.metallb.io \
  l2advertisements.metallb.io \
  --ignore-not-found
kubectl delete ds -n metallb-system speaker
kubectl delete deploy -n metallb-system controller
kubectl delete ns metallb-system
```

Output/expect:

```
validatingwebhookconfiguration.admissionregistration.k8s.io "metallb-webhook-configuration" deleted
clusterrole.rbac.authorization.k8s.io "metallb-system:controller" deleted
clusterrole.rbac.authorization.k8s.io "metallb-system:speaker" deleted
clusterrolebinding.rbac.authorization.k8s.io "metallb-system:controller" deleted
clusterrolebinding.rbac.authorization.k8s.io "metallb-system:speaker" deleted
customresourcedefinition.apiextensions.k8s.io "addresspools.metallb.io" deleted
customresourcedefinition.apiextensions.k8s.io "bfdprofiles.metallb.io" deleted
customresourcedefinition.apiextensions.k8s.io "bgpadvertisements.metallb.io" deleted
customresourcedefinition.apiextensions.k8s.io "bgppeers.metallb.io" deleted
customresourcedefinition.apiextensions.k8s.io "communities.metallb.io" deleted
customresourcedefinition.apiextensions.k8s.io "ipaddresspools.metallb.io" deleted
customresourcedefinition.apiextensions.k8s.io "l2advertisements.metallb.io" deleted
daemonset.apps "speaker" deleted
deployment.apps "controller" deleted
namespace "metallb-system" deleted
```

- This deletes resources to clear the way for a chart-based installation.

**RUN** **ONLY IF** previously installed by chart:

```
# RUN ONLY IF PREVIOUSLY INSTALLED BY CHART:
helm -n metallb-system uninstall metallb
```

Expected/ouput:

```
release "metallb" uninstalled
```

Run the _MetalLB_ install or upgrade:

**RUN**: the actual _MetalLB_ upgrade/install

```bash
# RUN
cd /opt/genestack
./bin/install-metallb.sh
```

Output/expect:

```
Found version for metallb: v0.15.2
"metallb" already exists with the same configuration, skipping
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "metallb" chart repository
Update Complete. ⎈Happy Helming!⎈
[DEBUG] HELM_REPO_URL=https://metallb.github.io/metallb
[DEBUG] HELM_REPO_NAME=metallb
[DEBUG] SERVICE_NAME=metallb
[DEBUG] HELM_CHART_PATH=metallb/metallb
Including base overrides from directory: /opt/genestack/base-helm-configs/metallb
 - /opt/genestack/base-helm-configs/metallb/metallb-helm-overrides.yaml
Including overrides from service config directory: /etc/genestack/helm-configs/metallb

Executing Helm command (arguments are quoted safely):
helm upgrade --install metallb metallb/metallb --version v0.15.2 --namespace=metallb-system --timeout 120m --create-namespace -f /opt/genestack/base-helm-configs/metallb/metallb-helm-overrides.yaml --post-renderer /etc/genestack/kustomize/kustomize.sh --post-renderer-args metallb/overlay
Release "metallb" does not exist. Installing it now.
NAME: metallb
LAST DEPLOYED: Thu Apr 30 20:20:58 2026
NAMESPACE: metallb-system
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
MetalLB is now running in the cluster.

Now you can configure it via its CRs. Please refer to the metallb official docs
on how to use the CRs.
```

- Expect the chart installation.
- Since we have to wipe out resources to complete the _kubespray_
  install, remove any conflicting resources and try again if they
  happen to block the installation. The above commands cleaned all
  resources in testing, but some environment(s) could theoretically
  have remaining conflicting resources that need removing to complete
  the chart installation.


Wait for _MetalLB_ to reconcile:

**RUN**: to wait for _MetalLB_ to reconcile before applying the config

```bash
# RUN
kubectl -n metallb-system wait deployment/metallb-controller --for=condition=Available --timeout=300s
kubectl -n metallb-system rollout status daemonset/metallb-speaker --timeout=300s || kubectl -n metallb-system rollout status daemonset/speaker --timeout=300s
```

Expect:

```
deployment.apps/metallb-controller condition met
daemon set "metallb-speaker" successfully rolled out
```

- We want this completed before proceeding to apply the config.


**RUN**: to reapply the site MetalLB address pool manifest

```bash
# RUN
kubectl apply -f \
/etc/genestack/manifests/metallb/metallb-openstack-service-lb.yml
```

Expect/output:

```
ipaddresspool.metallb.io/gateway-api-external created
l2advertisement.metallb.io/openstack-external-advertisement created
```

- Expect possible output variations by environment, this applies the
  configuration for the environment from /etc

**RUN** to validate _MetalLB_ CRs:

```bash
# RUN
kubectl -n metallb-system get ipaddresspools,l2advertisements
```

output/expect:

```
NAME                                            AUTO ASSIGN   AVOID BUGGY IPS   ADDRESSES
ipaddresspool.metallb.io/gateway-api-external   false         false             ["192.168.100.6/32"]

NAME                                                          IPADDRESSPOOLS             IPADDRESSPOOL SELECTORS   INTERFACES
l2advertisement.metallb.io/openstack-external-advertisement   ["gateway-api-external"]
```

- You should see that the resources got created/exist for your
  environment as per the just-applied configuration.

**RUN**: to verify the _Helm_ release:

```
# RUN
helm -n metallb-system list | grep metallb
```

Output/expect:

```
helm -n metallb-system list | grep metallb
metallb	metallb-system	1       	2026-04-30 20:20:58.930089998 +0000 UTC	deployed	metallb-0.15.2	v0.15.2
```

- We should see the chart **deployed** and at `v0.15.2`
- Fix any deployment errors or a bad deploy status at this point.

# Put new annotations in place


**RUN**: to create and save the deprecated _Service_ annotation inventory

```bash
# RUN
kubectl get svc -A -o json \
| jq -c '
  .items[]
  | . as $svc
  | ($svc.metadata.annotations // {}) as $a
  | ($a | to_entries | map(select(.key | startswith("metallb.universe.tf/")))) as $deprecated
  | select($deprecated | length > 0)
  | {
      namespace: $svc.metadata.namespace,
      kind: $svc.kind,
      name: $svc.metadata.name,
      deprecated_annotations: $deprecated
    }
' | grep -v metallb.universe.tf/ip-allocated-from-pool \
  | tee "$MAINT_DIR/metallb-deprecated-service-annotations.json"
```

Example output/expect:

```
{"namespace":"envoyproxy-gateway-system","kind":"Service","name":"envoy-envoy-gateway-flex-gateway-e868ef77","deprecated_annotations":[{"key":"metallb.universe.tf/address-pool","value":"gateway-api-external"}]}
{"namespace":"openstack","kind":"Service","name":"rabbitmq-nodes","deprecated_annotations":[{"key":"metallb.universe.tf/address-pool","value":"primary"}]}
```

* You should see some JSON output for deprecated annotations, although
  this varies by installation.
* each JSON line includes namespace, kind, name, and deprecated annotation key/value pairs
* lingering `metallb.universe.tf/ip-allocated-from-pool` is excluded
  from this inventory as automatically managed by _MetalLB_.
* You will use this file to create `metallb.io` keys with the same
  values, then remove the old keys.

# Redeploy

- As mentioned, _MetalLB_ deprecated prefix `metallb.universe.tf`, which
  means that we need the NEW prefix in place
- `v0.15.2` will continue to work with the deprecated key, but as a
  deprecated key, we can expect support for it to stop working at some
  point
- The deprecated keys don't cause any issues, so while not technically critical to
  get rid of them, you should definitely ensure that services have
  gotten redeployed such that they use the not-deprecated `metallb.io`
  prefix.
    - We go on to remove them later anyway to ensure they do not get
      replaced, which would indicate some _Deployment_, _Service_,
      CRD/CR, etc. has tried to replace them, and so might not place
      the new key.
- _MetalLB_ needs deployment *before* these services, especially when/if
  they have the deprecated keys.
    - because the `v0.15.2` respects the deprecated key, but `v0.13.x`
      doesn't recognize the new key.

**RUN**: the envoy gateway installation

```
# RUN
cd /opt/genestack
./bin/install-envoy-gateway.sh
kubectl -n envoyproxy-gateway-system rollout status \
deployment/envoy-gateway --timeout=300s
```

Output/expect:

- Normal installation of Envoy gateway (long output, looks like most
  of our install scripts do)
- Installation finishes rollout, with example output:

    ```
    deployment "envoy-gateway" successfully rolled out
    ```

**RUN**: _RabbitMQ_ cluster installation

```bash
# RUN
kubectl apply -k /etc/genestack/kustomize/rabbitmq-cluster/overlay
kubectl -n openstack get rabbitmqclusters.rabbitmq.com
kubectl get pod -A | grep -i rabbit
```

Output/Expect:

- Example outputs showing generally success:

    ```
    $ kubectl apply -k /etc/genestack/kustomize/rabbitmq-cluster/overlay
    poddisruptionbudget.policy/rabbitmq-disruption-budget configured
    rabbitmqcluster.rabbitmq.com/rabbitmq unchanged
    ```

    ```
    $ kubectl -n openstack get rabbitmqclusters.rabbitmq.com
    NAME       ALLREPLICASREADY   RECONCILESUCCESS   AGE
    rabbitmq   True               True               24h
    ```

    ```
    kubectl get pod -A | grep -i rabbit
    openstack                   rabbitmq-server-0                                                    1/1     Running     0             24h
    openstack                   rabbitmq-server-1                                                    1/1     Running     0             24h
    openstack                   rabbitmq-server-2                                                    1/1     Running     0             24h
    rabbitmq-system             messaging-topology-operator-557d9b6468-r779n                         1/1     Running     0             24h
    rabbitmq-system             rabbitmq-cluster-operator-9d5776865-dts7n                            1/1     Running     2 (24h ago)   24h
    ```

- Normal installation of RabbitMQ cluster
- Pods running normally, good cluster status
- Resolve any apparent issues

**RUN**: the MariaDB Cluster installation:

```
# RUN
kubectl --namespace openstack apply -k /etc/genestack/kustomize/mariadb-cluster/overlay
kubectl --namespace openstack get mariadb
kubectl get pod -A | grep -i mariadb
```

Output/expect:

- Example outputs generally showing success:

    ```
    $ kubectl --namespace openstack apply -k /etc/genestack/kustomize/mariadb-cluster/overlay
    configmap/mariadb-cluster unchanged
    backup.k8s.mariadb.com/mariadb-backup unchanged
    mariadb.k8s.mariadb.com/mariadb-cluster unchanged
    ```

    ```
    $ kubectl --namespace openstack get mariadb
    NAME              READY   STATUS    PRIMARY             UPDATES         AGE
    mariadb-cluster   True    Running   mariadb-cluster-0   RollingUpdate   24h
    ```

    ```
    $ kubectl get pod -A | grep -i mariadb
    mariadb-system              mariadb-operator-896f9f644-6hgwl                                     1/1     Running     2 (24h ago)   24h
    mariadb-system              mariadb-operator-896f9f644-7kdr2                                     1/1     Running     2 (24h ago)   24h
    mariadb-system              mariadb-operator-896f9f644-vjbds                                     1/1     Running     2 (24h ago)   24h
    mariadb-system              mariadb-operator-webhook-5448b4f575-65fbj                            1/1     Running     0             24h
    mariadb-system              mariadb-operator-webhook-5448b4f575-dzgs6                            1/1     Running     0             24h
    mariadb-system              mariadb-operator-webhook-5448b4f575-n2j2c                            1/1     Running     0             24h
    openstack                   mariadb-backup-29626560-psm2c                                        0/1     Pending     0             15h
    openstack                   mariadb-cluster-0                                                    1/1     Running     0             24h
    openstack                   mariadb-cluster-1                                                    1/1     Running     0             24h
    openstack                   mariadb-cluster-2                                                    1/1     Running     0             24h
    ```

- Resolve any apparent errors.

**RUN**: the Grafana installation

```
# RUN Grafana installation
cd /opt/genestack
./bin/install-grafana.sh
kubectl get pods -A | grep grafana
```

Expect/Output:

- Generally clean installation script output
- Pods running normally, etc:

    ```
    $ kubectl get pods -A | grep grafana
    grafana                     grafana-75d77bd44f-dzz8k                                             1/1     Running     2 (77s ago)   101s
    grafana                     mariadb-cluster-0                                                    1/1     Running     0             101s
    ```

- Resolve any issues with grafana pods, etc.

Annotate the services:

**RUN**: to find deprecated annotations

```
# RUN to find deprecated annotations
jq -r '
  . as $svc
  | .deprecated_annotations[]
  | select(.key != "metallb.universe.tf/ip-allocated-from-pool")
  | (.key | sub("^metallb\\.universe\\.tf/"; "metallb.io/")) as $newkey
  | "if kubectl -n \($svc.namespace) get svc/\($svc.name) >/dev/null 2>&1; then\n" +
    "  kubectl -n \($svc.namespace) annotate svc/\($svc.name) \($newkey)=" + (.value|@sh) + " --overwrite\n" +
    "  kubectl -n \($svc.namespace) annotate svc/\($svc.name) \(.key)- || true\n" +
    "else\n" +
    "  echo \"Skipping missing service \($svc.namespace)/\($svc.name)\"\n" +
    "fi"
' "$MAINT_DIR/metallb-deprecated-service-annotations.json" > "$MAINT_DIR/fix-metallb-service-annotations.sh"
cat "$MAINT_DIR/metallb-deprecated-service-annotations.json"
```

**RUN**: to review the output script

```
# RUN
less "$MAINT_DIR/fix-metallb-service-annotations.sh"
```

**RUN**: the script to fix annotations:

```
# RUN
bash "$MAINT_DIR/fix-metallb-service-annotations.sh"
```
Output/expect:

- Output from the cat looks something like:

    ```
    $ cat "$MAINT_DIR/metallb-deprecated-service-annotations.json"
    {"namespace":"envoyproxy-gateway-system","kind":"Service","name":"envoy-envoy-gateway-flex-gateway-e868ef77","deprecated_annotations":[{"key":"metallb.universe.tf/address-pool","value":"gateway-api-external"}]}
    {"namespace":"openstack","kind":"Service","name":"rabbitmq-nodes","deprecated_annotations":[{"key":"metallb.universe.tf/address-pool","value":"primary"}]}
    ```

    Script goes through each one, adds the new annotation, and removes
    old one, less output like:

    ```
    if kubectl -n envoyproxy-gateway-system get svc/envoy-envoy-gateway-flex-gateway-e868ef77 >/dev/null 2>&1; then
      kubectl -n envoyproxy-gateway-system annotate svc/envoy-envoy-gateway-flex-gateway-e868ef77 metallb.io/address-pool='gateway-api-external' --overwrite
      kubectl -n envoyproxy-gateway-system annotate svc/envoy-envoy-gateway-flex-gateway-e868ef77 metallb.universe.tf/address-pool- || true
    else
      echo "Skipping missing service envoyproxy-gateway-system/envoy-envoy-gateway-flex-gateway-e868ef77"
    fi
    if kubectl -n openstack get svc/rabbitmq-nodes >/dev/null 2>&1; then
      kubectl -n openstack annotate svc/rabbitmq-nodes metallb.io/address-pool='primary' --overwrite
      kubectl -n openstack annotate svc/rabbitmq-nodes metallb.universe.tf/address-pool- || true
    else
      echo "Skipping missing service openstack/rabbitmq-nodes"
    fi
    ```

- the script contains one add-new-key command and one remove-old-key
  command for each saved deprecated annotation
- every new `metallb.io` key uses the exact same saved value as the old
  key
- This generally shows still existing deprecated annotations, and shows
  that it will put the new annotations in place wherever they got found.

The script puts new annotations in place, and previous
grep checks on `opt` and `etc` _kustomize_ directories pre-confirmed that you had the
right commit so that services got redeployed with updated annotations.

We will perform a final validation pass and fix up any remaining
deprecated keys and ensure they get removed later.

# Post-Maint

**RUN**: verify the deployed version:

```bash
# RUN
grep '^[[:space:]]*metallb:' /etc/genestack/helm-chart-versions.yaml
kubectl -n metallb-system get deployment metallb-controller -o jsonpath='{range .spec.template.spec.containers[*]}{.image}{"\n"}{end}'
kubectl -n metallb-system get daemonset metallb-speaker -o jsonpath='{range .spec.template.spec.containers[*]}{.image}{"\n"}{end}' || kubectl -n metallb-system get daemonset speaker -o jsonpath='{range .spec.template.spec.containers[*]}{.image}{"\n"}{end}'
```

Expected:

```text
quay.io/metallb/controller:v0.15.2
quay.io/metallb/speaker:v0.15.2
quay.io/frrouting/frr:9.1.0
quay.io/frrouting/frr:9.1.0
quay.io/frrouting/frr:9.1.0
```

**RUN**: verify workload health:

```bash
# RUN
kubectl -n metallb-system get deployment,daemonset,pods
kubectl -n openstack get mariadb,rabbitmqclusters.rabbitmq.com
kubectl -n monitoring get pod -A | grep grafana
kubectl -n envoyproxy-gateway-system get deployment,pods
```

Expected:

* Example outputs:

    ```
    $ kubectl -n metallb-system get deployment,daemonset,pods
    NAME                                 READY   UP-TO-DATE   AVAILABLE   AGE
    deployment.apps/metallb-controller   1/1     1            1           21h

    NAME                             DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR            AGE
    daemonset.apps/metallb-speaker   3         3         3       3            3           kubernetes.io/os=linux   21h

    NAME                                      READY   STATUS    RESTARTS      AGE
    pod/metallb-controller-5754956df6-m8tzt   1/1     Running   2 (21h ago)   21h
    pod/metallb-speaker-4szzj                 4/4     Running   0             21h
    pod/metallb-speaker-vjlqs                 4/4     Running   0             21h
    pod/metallb-speaker-vz4db                 4/4     Running   0             21h
    ```

    ```
    $ kubectl -n openstack get mariadb,rabbitmqclusters.rabbitmq.com
    NAME                                      READY   STATUS    PRIMARY             UPDATES         AGE
    mariadb.k8s.mariadb.com/mariadb-cluster   True    Running   mariadb-cluster-0   RollingUpdate   26h

    NAME                                    ALLREPLICASREADY   RECONCILESUCCESS   AGE
    rabbitmqcluster.rabbitmq.com/rabbitmq   True               True               26h
    ```

    ```
    $ kubectl -n monitoring get pod -A | grep grafana
    grafana                     grafana-75d77bd44f-dzz8k                                             1/1     Running     2 (152m ago)   152m
    grafana                     mariadb-cluster-0                                                    1/1     Running     0              152m
    ```

    ```
    $ kubectl -n envoyproxy-gateway-system get deployment,pods
    NAME                                                        READY   UP-TO-DATE   AVAILABLE   AGE
    deployment.apps/envoy-envoy-gateway-flex-gateway-e868ef77   2/2     2            2           26h
    deployment.apps/envoy-gateway                               1/1     1            1           26h

    NAME                                                             READY   STATUS    RESTARTS   AGE
    pod/envoy-envoy-gateway-flex-gateway-e868ef77-5dc6f54998-h56xk   2/2     Running   0          26h
    pod/envoy-envoy-gateway-flex-gateway-e868ef77-5dc6f54998-pfgjz   2/2     Running   0          26h
    pod/envoy-gateway-d7bbd95f5-jf4t6                                1/1     Running   0          26h
    ubuntu@hyperconverged-metallb-033-0:~$
    ```

* metallb-controller is Available
* MetalLB speaker daemonset is Ready on expected nodes
* MariaDB is present and its pods are Running
* RabbitMQ cluster is present and its pods are Running
* Grafana pods are Running and Ready
* Envoy Gateway deployment is Available

**RUN**: verify dependent services

```bash
# RUN
kubectl -n openstack get svc | egrep 'mariadb|rabbit'
kubectl -n monitoring get svc -A | grep grafana || true
kubectl -n openstack get httproute || true
kubectl -n envoy-gateway get gateways.gateway.networking.k8s.io flex-gateway || true
```

Output/expect:

- Example outputs:

    ```
    $ kubectl -n openstack get svc | egrep 'mariadb|rabbit'
    mariadb-cluster             LoadBalancer   10.233.26.11    <pending>     3306:32271/TCP                                                                                                                 26h
    mariadb-cluster-internal    ClusterIP      None            <none>        3306/TCP                                                                                                                       26h
    mariadb-cluster-primary     LoadBalancer   10.233.61.176   <pending>     3306:31971/TCP                                                                                                                 26h
    mariadb-cluster-secondary   LoadBalancer   10.233.11.233   <pending>     3306:32136/TCP                                                                                                                 26h
    rabbitmq                    LoadBalancer   10.233.6.87     <pending>     1883:32659/TCP,15675:30868/TCP,61613:30796/TCP,15674:31017/TCP,5552:32431/TCP,15692:30849/TCP,5672:31822/TCP,15672:31351/TCP   26h
    rabbitmq-nodes              ClusterIP      None            <none>        4369/TCP,25672/TCP                                                                                                             26h
    ```

    ```
    $ kubectl -n monitoring get svc -A | grep grafana || true
    grafana                     grafana                                          ClusterIP      10.233.9.23     <none>          80/TCP                                                                                                                         155m
    grafana                     mariadb-cluster                                  LoadBalancer   10.233.44.146   <pending>       3306:31671/TCP                                                                                                                 155m
    grafana                     mariadb-cluster-internal                         ClusterIP      None            <none>          3306/TCP                                                                                                                       155m
    ```

    ```
    $ kubectl -n openstack get httproute || true
    NAME                                  HOSTNAMES                          AGE
    custom-barbican-gateway-route         ["barbican.cluster.local"]         26h
    custom-blazar-gateway-route           ["blazar.cluster.local"]           26h
    custom-cinder-gateway-route           ["cinder.cluster.local"]           26h
    custom-cloudformation-gateway-route   ["cloudformation.cluster.local"]   26h
    custom-cloudkitty-gateway-route       ["cloudkitty.cluster.local"]       26h
    custom-freezer-gateway-route          ["freezer.cluster.local"]          26h
    custom-glance-gateway-route           ["glance.cluster.local"]           26h
    custom-gnocchi-gateway-route          ["gnocchi.cluster.local"]          26h
    custom-heat-gateway-route             ["heat.cluster.local"]             26h
    custom-ironic-gateway-route           ["ironic.cluster.local"]           26h
    custom-keystone-gateway-route         ["keystone.cluster.local"]         26h
    custom-magnum-gateway-route           ["magnum.cluster.local"]           26h
    custom-manila-gateway-route           ["manila.cluster.local"]           26h
    custom-masakari-gateway-route         ["masakari.cluster.local"]         26h
    custom-metadata-gateway-route         ["metadata.cluster.local"]         26h
    custom-neutron-gateway-route          ["neutron.cluster.local"]          26h
    custom-nova-gateway-route             ["nova.cluster.local"]             26h
    custom-novnc-gateway-route            ["novnc.cluster.local"]            26h
    custom-octavia-gateway-route          ["octavia.cluster.local"]          26h
    custom-placement-gateway-route        ["placement.cluster.local"]        26h
    custom-skyline-gateway-route          ["skyline.cluster.local"]          26h
    custom-trove-gateway-route            ["trove.cluster.local"]            26h
    custom-zaqar-gateway-route            ["zaqar.cluster.local"]            26h
    http2https-route                      ["*.cluster.local"]                26h
    ```

    ```
    $ kubectl -n envoy-gateway get gateways.gateway.networking.k8s.io flex-gateway || true
    NAME           CLASS   ADDRESS         PROGRAMMED   AGE
    flex-gateway   eg      192.168.100.6   True         26h
    ```

- These sorts of resources should exist and look healthy, expect minor
  variation by environment, installed components, etc.

**RUN**: verify logs or events for upgrade failures:

```bash
kubectl logs -n metallb-system deployment/metallb-controller --tail=100
kubectl logs -n envoyproxy-gateway-system deployment/envoy-gateway --tail=100
kubectl get events -A --sort-by='.lastTimestamp' | tail -n 100
```

**RUN**: Final sweep to ensure all services have the new annotation

```
# RUN
kubectl get service -A -o json |
jq -r '
  .items[]
  | (.metadata.annotations // {}) as $ann
  | (
      $ann
      | to_entries
      | map(select(
          (.key | startswith("metallb.universe.tf/"))
          and .key != "metallb.universe.tf/ip-allocated-from-pool"
        ))
      | from_entries
    ) as $deprecated
  | (
      $ann
      | to_entries
      | map(select(
          (.key | startswith("metallb.io/"))
          and .key != "metallb.io/ip-allocated-from-pool"
        ))
      | from_entries
    ) as $current
  | select(
      ($deprecated | length > 0)
      or
      ($current | length > 0)
    )
  | {
      namespace: .metadata.namespace,
      name: .metadata.name,
      deprecated_annotations: $deprecated,
      current_annotations: $current
    }
'
```

Expect/Example output (trucated):

```
{
  "namespace": "envoyproxy-gateway-system",
  "name": "envoy-envoy-gateway-flex-gateway-e868ef77",
  "deprecated_annotations": {
    "metallb.universe.tf/address-pool": "gateway-api-external"
  },
  "current_annotations": {
    "metallb.io/address-pool": "gateway-api-external"
  }
}
{
  "namespace": "envoyproxy-gateway-system",
  "name": "envoy-rackspace-flex-rax-gateway-3b619720",
  "deprecated_annotations": {
    "metallb.universe.tf/address-pool": "gateway-api-external"
  },
  "current_annotations": {
    "metallb.io/address-pool": "gateway-api-external"
  }
}
```

- As previously mentioned, the deprecated annotations cause no problem,

  BUT:

    - We clean them up to ensure nothing replaces them, which probably
      would indicate that it does not place the new not-deprecated key,

  AND

    - We must have the
      new, proper annotation with the same key (with the `metallb.io`
      path instead of `metallb.universe.tf`) and value

- We verified no `metallb.universe.tf` in _kustomize_, etc. in previous
  steps with commands like:

     ```
     # No need to run this here
     grep -R "metallb.universe.tf/" /opt/genestack/base-kustomize || true
     grep -R "metallb.universe.tf/" /etc/genestack/helm-configs /etc/genestack/kustomize || true
     ```

     and subsequently redeployed them.

- So here we need to ensure that services have the correct annotation
- _MetalLB_ uses `metallb.io/ip-allocated-from-pool` and
  `metallb.universe.tf/ip-allocated-from-pool` for internal record
  keeping and management, and so we excluded these and do not manipulate
  them directly.

**RUN**: remove deprecated service annotations for each deprecated key above

```
# RUN
kubectl -n <namepsace> annotate svc/<servicename> metallb.universe.tf/<rest of key>-
```

Expect/example output:

```
service/rabbitmq-nodes annotated
```

- **Ensure you have an identical key value pair except with**
  **`metallb.io` prior to removing the deprecated keys**

**RUN**: Wait 5 minutes and rerun the step checking for deprecated keys

```
# RUN
# see above step to repeat the final sweep
```

output/expect:

- example output:

    ```
    {
      "namespace": "envoyproxy-gateway-system",
      "name": "envoy-envoy-gateway-flex-gateway-e868ef77",
      "deprecated_annotations": {},
      "current_annotations": {
        "metallb.io/address-pool": "gateway-api-external"
      }
    }
    {
      "namespace": "grafana",
      "name": "mariadb-cluster",
      "deprecated_annotations": {},
      "current_annotations": {
        "metallb.io/address-pool": "primary"
      }
    }
    ```

- **Deprecated keys should not reappear**, as this would indicate
  some Deployment, etc. has replaced the deprecated key, which could
  cause a problem in a future version of _MetalLB_ not respecting the
  deprecated key, while this version does respect it.

**RUN**: to verify logs or events for upgrade failures:

```
# RUN
kubectl logs -n metallb-system deployment/metallb-controller --tail=100
```

Expect/output:

```
{"caller":"service_controller.go:64","controller":"ServiceReconciler","level":"info","start reconcile":"redis-systems/redis-replication-master","ts":"2026-05-01T18:44:31Z"}
{"caller":"service_controller.go:115","controller":"ServiceReconciler","end reconcile":"redis-systems/redis-replication-master","level":"info","ts":"2026-05-01T18:44:31Z"}
{"caller":"service_controller.go:64","controller":"ServiceReconciler","level":"info","start reconcile":"redis-systems/redis-replication-replica","ts":"2026-05-01T18:44:31Z"}
{"caller":"service_controller.go:115","controller":"ServiceReconciler","end reconcile":"redis-systems/redis-replication-replica","level":"info","ts":"2026-05-01T18:44:31Z"}
```

- You'll probably see reconciliations.
- Keep in mind you might see some transient errors from deploy.
- As an example from a hyperconverged lab with a problem:

   ```
   {"caller":"service.go:179","error":"unknown pool \"primary\"","level":"error","msg":"IP allocation failed","op":"allocateIPs","ts":"2026-05-01T18:31:27Z"}
   ```

   In that case, you would review pools and keys, but this generally
   shouldn't happen with pre-existing working configuration.

**RUN**: to verify logs or events for upgrade failures:

```
kubectl logs -n envoyproxy-gateway-system deployment/envoy-gateway --tail=100
```

Expect/output:

- Example output (truncated):

    ```
    2026-05-01T19:04:43.359Z        INFO    provider        kubernetes/status_updater.go:143        received a status update        {"runner": "provider", "namespace": "envoy-gateway", "name": "flex-gateway", "kind": "Gateway"}
    ```

- No particular known issues to look for here

**RUN**: kubernetes event checks

```
# RUN
kubectl get events -A --sort-by='.lastTimestamp' | tail -n 100
```

Expect/output:

- No known particular issues to look for

**RUN**: Manual checks

- **RUN** run the site-standard OpenStack API health check and confirm success

    ```
    # RUN locally/from your laptop/workstation
    env OS_CLOUD=<environment> openstack token issue
    ```

- **RUN** confirm Grafana is reachable through the site's normal path
- **RUN** confirm the expected Envoy-backed routes remain reachable
- **RUN** confirm RabbitMQ clients reconnect normally if applicable

Expected:

* Keystone issues token
* expected LoadBalancer services still have addresses
* no non-ignored deprecated metallb.universe.tf annotations remain
* user-facing paths remain reachable

## Troubleshooting

# Common Failure Signal

If deprecated `metallb.universe.tf` annotations reappear after you remove
them, stop and do not continue to post-maint signoff.

This indicates that a managing chart, override, CR, or manifest still
contains the deprecated key and is reconciling it back.

# RabbitMQ Longhorn or PVC restart issue

If RabbitMQ pods fail to restart because of the site-specific Longhorn
or PVC issue, follow the site's approved PVC recovery procedure before
continuing. You may need to delete the RabbitMQ PVCs to proceed.

## Sources

* [https://docs.rackspacecloud.com/infrastructure-metallb/](https://docs.rackspacecloud.com/infrastructure-metallb/)
* [https://docs.rackspacecloud.com/infrastructure-envoy-gateway-api/](https://docs.rackspacecloud.com/infrastructure-envoy-gateway-api/)
* [https://docs.rackspacecloud.com/monitoring-grafana/](https://docs.rackspacecloud.com/monitoring-grafana/)
* [https://docs.rackspacecloud.com/infrastructure-rabbitmq/](https://docs.rackspacecloud.com/infrastructure-rabbitmq/)
* [https://docs.rackspacecloud.com/infrastructure-mariadb/](https://docs.rackspacecloud.com/infrastructure-mariadb/)
* [https://docs.rackspacecloud.com/genestack-structure-and-files/](https://docs.rackspacecloud.com/genestack-structure-and-files/)
* [https://docs.rackspacecloud.com/release-notes/](https://docs.rackspacecloud.com/release-notes/)
* [https://metallb.io/installation/](https://metallb.io/installation/)
* [https://metallb.io/release-notes/](https://metallb.io/release-notes/)
