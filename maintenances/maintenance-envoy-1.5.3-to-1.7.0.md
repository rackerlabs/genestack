# Envoy Gateway Maintenance: 1.5.3 to 1.7.0

## Notes

(opt) refers to /opt, the standard install path for Genestack.

(etc) refers to /etc, the standard override path for Genestack.

This runbook upgrades Envoy Gateway CRDs first, then upgrades Envoy Gateway

Depending on your deployment, your steps may need to be adjusted, but CRDs should always be upgraded first.

## Validation

### Validated source version:

`Envoy Gateway 1.5.3`

### Validated target version:

`Envoy Gateway 1.7.0`

### Supported upgrade path:

Direct upgrade from Envoy Gateway 1.5.3 to 1.7.0

> **_NOTE:_**
>
> If using BackendTLSPolicy, you should consider doing an incremental upgrade.
> https://github.com/envoyproxy/gateway/issues/7709

Incremental upgrade: 1.5.3 -> 1.5.8 -> 1.7.0

- Upgrade gateway-helm to v1.5.8 (before touching CRDs — this version correctly handles BackendTLSPolicy CRD detection after a CRD upgrade)
- Upgrade Gateway API CRDs to v1.4.1-experimental
- Upgrade gateway-helm to your target version v1.7.0
- Update BackendTLSPolicy resources from apiVersion: gateway.networking.k8s.io/v1alpha3 to v1 in your manifests
- Optionally switch to v1.4.1-standard CRDs once all resources are on v1
- convert any `BackendTLSPolicy` resources from `v1alpha3` to `v1`

### Major operational risks:

- brief interruption of LoadBalancer service reconciliation

## Goal

Upgrade Envoy CRDs to either v1.4.1 or v1.5.1 (experimental)
Upgrade Envoy Gateway from 1.5.3 to 1.7.0.

## Prep

# Deployment Node

### Use the Genestack deployment host or bastion that has:

- kubectl access to the target cluster
- helm, jq, yq, grep, sed
- /opt/genestack checked out to the target Genestack release
- /etc/genestack populated for the target site

### Create a working directory for this maintenance:

    export MAINT_DIR=/home/ubuntu/envoy-1.5.3-maint
    mkdir -p "$MAINT_DIR"

### Backup current components:

    kubectl get crd -A -o yaml > "$MAINT_DIR/crds-all.yaml"
    kubectl get gateway -A -o yaml > "$MAINT_DIR/gateways-all.yaml"
    kubectl get httproute -A -o yaml > "$MAINT_DIR/httproutes-all.yaml"
    kubectl get gatewayclass -A -o yaml > "$MAINT_DIR/gatewayclasses-all.yaml"
    kubectl get envoyproxy,clienttrafficpolicy,backendtrafficpolicy,securitypolicy -A -o yaml > "$MAINT_DIR/envoy-gateway-resources.yaml"
    helm get values envoyproxy-gateway -n envoyproxy-gateway-system -a > "$MAINT_DIR/helm-values.yaml"


### Verify current cluster or platform health:

    kubectl get nodes
    kubectl get pods -A --no-headers | awk '$4 != "Running" && $4 != "Completed" {print}'

### Verify the current deployed version:

    helm -n envoyproxy-gateway-system list
    kubectl -n envoyproxy-gateway-system get deployment envoy-gateway -o jsonpath='{range .spec.template.spec.containers[*]}{.image}{"\n"}{end}'

### Verify CRD version:

    for crd in $(kubectl get crd -o name | grep 'gateway.networking.k8s.io'); do
      echo "=== $crd ==="
      echo -n "bundle-version: "
      kubectl get "$crd" -o jsonpath='{.metadata.annotations.gateway\.networking\.k8s\.io/bundle-version}'
      echo
      echo -n "channel: "
      kubectl get "$crd" -o jsonpath='{.metadata.annotations.gateway\.networking\.k8s\.io/channel}'
      echo
      echo -n "served versions: "
      kubectl get "$crd" -o jsonpath='{range .spec.versions[*]}{.name}{" "}{end}'
      echo
      echo
    done

    for crd in $(kubectl get crd -o name | grep 'gateway.envoyproxy.io'); do
      echo "=== $crd ==="
      echo -n "established: "
      kubectl get "$crd" -o jsonpath='{range .status.conditions[?(@.type=="Established")]}{.status}{end}'
      echo
      echo -n "accepted names: "
      kubectl get "$crd" -o jsonpath='{.status.acceptedNames.kind}'
      echo
      echo -n "served versions: "
      kubectl get "$crd" -o jsonpath='{range .spec.versions[*]}{.name}{"("}{.served}{") "}{end}'
      echo
      echo
    done

### Expected:

- Helm release at version 1.5.3
- CRDS at version 1.3.0
- Gateway API CRDs show the expected current bundle-version
- Gateway API CRDs show the expected channel
- Envoy Gateway CRDs are `Established=True`
- Envoy Gateway CRDs serve `v1alpha1`

If the current version does not match Envoy Gateway 1.5.3, stop and reassess.  This upgrade was not tested with any other 1.5.X versions

### Verify node or workload placement, if relevant:

    Not relevant for this maintenance.

### Verify backups, snapshots, or restore points are available:

    ls "$MAINT_DIR"

### Expected:

- Envoy Gateway backup files exist in $MAINT_DIR

If backups are required but missing, stop and create them before continuing.

# Configuration Review

Identify the configuration files or values that control this component:

    /etc/genestack/helm-chart-versions.yaml
    /opt/genestack/base-kustomize/envoyproxy-gateway/
    /etc/genestack/kustomize/envoyproxy-gateway/
    /etc/genestack/helm-configs/envoyproxy-gateway

### Verify the current config:

    grep '^[[:space:]]*envoyproxy-gateway:' /etc/genestack/helm-chart-versions.yaml

### Expected:

- /etc/genestack/helm-chart-versions.yaml contains envoyproxy-gateway: v1.5.3 before the install step

If any non-standard override exists, document it in the maintenance log before continuing.

# Pre-Change Safety Checks

### Check for unhealthy pods, jobs, or dependent services:

    kubectl get pods -A --no-headers | awk '$4 != "Running" && $4 != "Completed" {print}'

### Check for open alerts or known blockers:

    kubectl get events -A --sort-by='.lastTimestamp' | tail -n 100

## Execute

### Bump the Target Version

    sed -E -i 's/^([[:space:]]*envoyproxy-gateway:[[:space:]]*)v[0-9.]+/\1v1.7.0/' /etc/genestack/helm-chart-versions.yaml

### Verify the version is updated:

    grep '^[[:space:]]*envoyproxy-gateway:' /etc/genestack/helm-chart-versions.yaml

### Expect:

    envoyproxy-gateway: v1.7.0

For this runbook, intermediate Envoy Gateway version is required ONLY if using `BackendTLSPolicy`

# Run the Maintenance

## Upgrade CRDs

*IF NOT USING EXPERIMENTAL CRDS*

    cd "$MAINT_DIR"
    helm pull oci://docker.io/envoyproxy/gateway-helm --version v1.7.0 --untar
    kubectl apply --force-conflicts --server-side -f ./gateway-helm/crds/gatewayapi-crds.yaml
    kubectl apply --force-conflicts --server-side -f ./gateway-helm/crds/generated

*IF USING EXPERIMENTAL CRDS*

    cd "$MAINT_DIR"
    kubectl apply --server-side --force-conflicts \
      -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/experimental-install.yaml
    helm template eg-crds oci://docker.io/envoyproxy/gateway-crds-helm \
      --version v1.7.0 \
      --set crds.gatewayAPI.enabled=true \
      --set crds.gatewayAPI.channel=experimental \
      --set crds.envoyGateway.enabled=true \
      | kubectl apply --server-side -f -

### Check CRD version

    for crd in $(kubectl get crd -o name | grep 'gateway.networking.k8s.io'); do
      echo "=== $crd ==="
      echo -n "bundle-version: "
      kubectl get "$crd" -o jsonpath='{.metadata.annotations.gateway\.networking\.k8s\.io/bundle-version}'
      echo
      echo -n "channel: "
      kubectl get "$crd" -o jsonpath='{.metadata.annotations.gateway\.networking\.k8s\.io/channel}'
      echo
      echo -n "served versions: "
      kubectl get "$crd" -o jsonpath='{range .spec.versions[*]}{.name}{" "}{end}'
      echo
      echo
    done

    for crd in $(kubectl get crd -o name | grep 'gateway.envoyproxy.io'); do
      echo "=== $crd ==="
      echo -n "established: "
      kubectl get "$crd" -o jsonpath='{range .status.conditions[?(@.type=="Established")]}{.status}{end}'
      echo
      echo -n "accepted names: "
      kubectl get "$crd" -o jsonpath='{.status.acceptedNames.kind}'
      echo
      echo -n "served versions: "
      kubectl get "$crd" -o jsonpath='{range .spec.versions[*]}{.name}{"("}{.served}{") "}{end}'
      echo
      echo
    done


### Expected:

- Networking CRD: versions at 1.4.1 OR 1.5.1 depending on which upgrade path you did
- EnvoyProxy CRD: `Established=True`; Served versions include v1alpha1(true)

## Upgrade Envoy Gateway

    /opt/genestack/bin/install-envoy-gateway.sh

### Check Envoy Gateway version

    helm list -n envoyproxy-gateway-system -f envoyproxy-gateway -o json | jq -r '.[0].app_version'


### Expected:

- App Version should be at v1.7.0

## Post-Maint

### Verify the deployed version:

    grep '^[[:space:]]*envoyproxy-gateway:' /etc/genestack/helm-chart-versions.yaml
    kubectl get deployments -n envoyproxy-gateway-system -o json \
    | jq -r '
      .items[]
      | .metadata.name as $name
      | .spec.template.spec.containers[]
      | "\($name)\t\(.name)\t\(.image)"
    ' | column -t

### Expected:

- App Version should be at v1.7.0
- Images should be docker.io/envoyproxy/envoy:distroless-v1.37.0 and/or docker.io/envoyproxy/gateway:v1.7.0

### Verify workload health:

    kubectl -n envoyproxy-gateway-system get deployment,pods

### Expected:

- envoy-gateway is available
- envoy pods are in a `Running` status

### Verify logs or events for upgrade failures:

    kubectl logs -n envoyproxy-gateway-system deployment/envoy-gateway --tail=100
    kubectl get events -A --sort-by='.lastTimestamp' | tail -n 100

### Verify user-facing functionality:

    curl -is https://keystone.<YOUR_DOMAIN>/v3

### Expected:

- 200 OK status in header and dictionary in body

# Troubleshooting

## Common Failure Signal

- kubectl apply --server-side for the CRDs fails with conflicts, validation errors, or no matches for kind
- envoy-gateway in envoyproxy-gateway-system does not become Available
- kubectl -n envoy-gateway get gateway shows the Gateway is not Accepted or not Programmed
- kubectl get httproute -A shows routes with unresolved parents or invalid status conditions
- Envoy proxy pods fail to start, crash loop, or never become Ready
- User-facing endpoint checks such as curl -k https://keystone.<YOUR_DOMAIN>/v3 fail, time out, or return 5xx
- Controller logs show schema or reconciliation errors after the upgrade
- Helm upgrade fails because a post-rendered dependency is missing, such as a referenced namespace or CRD

### CRD apply fails

- Confirm you used the correct CRD channel: experimental if the site already uses experimental CRDs
- Re-run the CRD apply step before retrying the Helm upgrade
- If using BackendTLSPolicy, stop and reassess whether the incremental path is required

### Helm upgrade fails

- Check whether the failure is in the Helm chart itself or in Genestack post-rendered manifests
- If the failure mentions a missing namespace or rendered object, fix that dependency first and rerun the install
- Do not proceed until Helm reports a healthy release

### Gateway or routes are not accepted

- Look for route validation failures introduced by the newer Envoy Gateway version
- Check for invalid filters or policy references

### User-facing traffic fails after upgrade

- Confirm the Gateway is accepted and programmed
- Confirm Envoy proxy pods are running and ready
- Check logs from both envoy-gateway and any Envoy data-plane pods

# Rollback

## Rollback trigger:

- Envoy Gateway fails to become healthy
- HTTPRoutes no longer work

### Rollback procedure

    helm -n envoyproxy-gateway-system history envoyproxy-gateway
    helm -n envoyproxy-gateway-system rollback envoyproxy-gateway <previous version>

> **_NOTE:_**
> Do not rollback CRDs.  If CRD rollback is necessary, a "nuke and rebuild" of envoy-gateway is a better option
   
### Expected:

- Envoy Gateway returns to the previous healthy Helm revision
- HTTPRoute reachability is restored

## Sources

https://gateway.envoyproxy.io/news/releases/v1.7/

https://gateway.envoyproxy.io/docs/install/install-helm/#upgrading-from-the-previous-version

https://docs.rackspacecloud.com/infrastructure-envoy-gateway-api/

https://docs.rackspacecloud.com/genestack-structure-and-files/

https://docs.rackspacecloud.com/release-notes/

