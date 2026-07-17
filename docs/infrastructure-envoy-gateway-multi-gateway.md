---
hide:
  - footer
---

# Envoy Gateway Internal and External Gateway Runbooks

Genestack can deploy Envoy Gateway in the original single gateway mode or in
multi-gateway config mode. The original mode creates one `flex-gateway`.
Config mode creates separate gateways, usually named `external` and `internal`,
with separate GatewayClasses, MetalLB pools, listeners, certificates, and
HTTPRoutes.

Use config mode when routes need to be explicitly published as:

- `external`: reachable through the external gateway only.
- `internal`: reachable through the internal gateway only.
- `both`: rendered for both gateways.
- `skip`: intentionally not rendered in the new config.

The generated configuration file is normally:

``` shell
/etc/genestack/envoy-gateways.yaml
```

When using config mode, use `install-envoy-gateway.sh --config` instead of
calling only `setup-envoy-gateway.sh --config`. The install script updates the
Envoy Helm release to use the config-mode post-renderer and then applies the
configured gateways and routes.

!!! warning
    Running config mode is a cutover. The setup step removes the legacy
    `flex-gateway` and creates the configured gateways. Capture route state and
    prepare DNS/VIP validation before running the cutover.

## Configuration File Shape

The config file defines global settings, optional ACME settings, gateways, and
routes.

``` yaml
domain: example.com

acme:
  enabled: true
  email: cloud@example.com
  issuer: letsencrypt-prod
  gateway: external

gateways:
  external:
    enabled: true
    namespace: envoy-gateway
    type: external
    domain: example.com
    gateway_class: external-eg
    issuer: letsencrypt-prod
    metallb_pool: gateway-api-external
    certificate_secret: wildcard-external-tls-secret

  internal:
    enabled: true
    namespace: envoy-gateway
    type: internal
    domain: internal.example.com
    gateway_class: internal-eg
    issuer: flex-gateway-issuer
    metallb_pool: gateway-api-internal
    certificate_secret: wildcard-internal-tls-secret

routes:
  - name: keystone
    exposure: external
    section_name: keystone-https

  - name: prometheus
    exposure: internal
    section_name: cluster-tls
```

Known Genestack route names use the existing route templates from
`/opt/genestack/etc/gateway-api/routes`. Unknown route names can still be used
when the route entry includes `namespace`, `service`, `service_namespace`,
`port`, and optionally `hostname`.

## New Hyperconverged Lab With Internal and External Gateways

This path builds a new lab directly in config mode. The lab automation creates
the second internal MetalLB VIP port when config mode is enabled.

### Prerequisites

- OpenStack CLI access from the workstation running the lab script.
- A `GATEWAY_DOMAIN` that you control if testing real DNS or Let's Encrypt.
- An `ACME_EMAIL` if using Let's Encrypt for external routes.
- A development checkout if testing unmerged changes with
  `HYPERCONVERGED_DEV=true`.

### Deploy Without Let's Encrypt

``` shell
export OS_CLOUD=default
export HYPERCONVERGED_DEV=true
export GATEWAY_DOMAIN=example.com
export OS_IMAGE="Ubuntu 24.04"
export OS_FLAVOR=gp.0.8.16
export SSH_USERNAME=ubuntu

./scripts/hyperconverged-lab.sh kubespray --envoy-gateway-config
```

The same mode can be enabled with environment variables:

``` shell
export HYPERCONVERGED_ENVOY_GATEWAY_CONFIG=true
./scripts/hyperconverged-lab.sh kubespray
```

### Deploy With Let's Encrypt for External Routes

``` shell
export OS_CLOUD=default
export HYPERCONVERGED_DEV=true
export GATEWAY_DOMAIN=example.com
export ACME_EMAIL=cloud@example.com
export OS_IMAGE="Ubuntu 24.04"
export OS_FLAVOR=gp.0.8.16
export SSH_USERNAME=ubuntu

./scripts/hyperconverged-lab.sh kubespray --envoy-gateway-acme
```

ACME mode sets the external gateway issuer to `letsencrypt-prod` and keeps the
internal gateway on the internal issuer. External OpenStack API routes use
per-service HTTPS listeners so cert-manager can issue certificates for each
external hostname.

### Use a Fixed Internal MetalLB IP

If the internal VIP must be a specific address, pass it explicitly:

``` shell
./scripts/hyperconverged-lab.sh kubespray \
  --envoy-gateway-config \
  --internal-metallb-ip 192.168.100.110
```

Or use the environment variable:

``` shell
export HYPERCONVERGED_ENVOY_GATEWAY_CONFIG=true
export HYPERCONVERGED_INTERNAL_METALLB_IP=192.168.100.110
./scripts/hyperconverged-lab.sh kubespray
```

### Validate the Lab

The deployment summary shows whether config mode was enabled and which MetalLB
addresses were assigned:

``` text
Envoy Gateway Config Mode: true
Envoy Gateway ACME Mode: true
MetalLB External IP: 192.168.100.50
MetalLB Envoy Internal IP: 192.168.100.110
```

From the jump host:

``` shell
kubectl get gateway -A -o wide
kubectl get gatewayclass
kubectl get httproute -A -o wide
kubectl get svc -n envoyproxy-gateway-system
kubectl get ipaddresspool,l2advertisement -n metallb-system
sudo test -f /etc/genestack/envoy-gateways.yaml
```

Expected objects include:

- `GatewayClass/external-eg`
- `GatewayClass/internal-eg`
- `Gateway/envoy-gateway/external`
- `Gateway/envoy-gateway/internal`
- `IPAddressPool/gateway-api-external`
- `IPAddressPool/gateway-api-internal`

Test representative routes:

``` shell
curl -vk --resolve keystone.example.com:443:<external-vip> \
  https://keystone.example.com/v3

curl -vk --resolve prometheus.internal.example.com:443:<internal-vip> \
  https://prometheus.internal.example.com/
```

## Convert an Existing Hyperconverged Lab

This path starts with a lab that was deployed in the original single
`flex-gateway` mode and converts it in place.

### 1. Capture the Current State

Run these commands from the jump host:

``` shell
kubectl get gateway,gatewayclass,httproute,certificate -A -o wide
kubectl get svc -n envoyproxy-gateway-system
kubectl get ipaddresspool,l2advertisement -n metallb-system

sudo /opt/genestack/scripts/cleanup-envoy-httproutes.sh snapshot \
  --output /etc/genestack/envoy-httproutes-before-cutover.json \
  --force
```

Keep a second terminal open with a watch while performing the cutover:

``` shell
watch -n2 'kubectl get gateway -A; echo; kubectl get svc -n envoyproxy-gateway-system'
```

### 2. Prepare the Internal MetalLB VIP

The original lab has only the external MetalLB VIP. Create a second OpenStack
port for the internal Envoy VIP from the workstation where the OpenStack CLI is
configured:

``` shell
export LAB_NAME_PREFIX=${LAB_NAME_PREFIX:-hyperconverged}

export METAL_LB_INTERNAL_IP=$(
  openstack port create \
    --security-group ${LAB_NAME_PREFIX}-http-secgroup \
    --network ${LAB_NAME_PREFIX}-net \
    ${LAB_NAME_PREFIX}-metallb-internal-vip-0-port \
    -f json | jq -r '.fixed_ips[0].ip_address'
)

echo "${METAL_LB_INTERNAL_IP}"
```

Allow the new VIP on the lab node management ports:

``` shell
for port in \
  ${LAB_NAME_PREFIX}-0-mgmt-port \
  ${LAB_NAME_PREFIX}-1-mgmt-port \
  ${LAB_NAME_PREFIX}-2-mgmt-port; do
  port_id=$(openstack port show "${port}" -f value -c id)
  openstack port set --allowed-address "ip-address=${METAL_LB_INTERNAL_IP}" "${port_id}"
done
```

On the jump host, write and apply the updated MetalLB manifest. Replace the IPs
with the external MetalLB IP from the lab summary and the new internal VIP:

``` shell
export METAL_LB_EXTERNAL_IP=<existing-external-metallb-ip>
export METAL_LB_INTERNAL_IP=<new-internal-metallb-ip>

sudo env METAL_LB_INTERNAL_IP="${METAL_LB_INTERNAL_IP}" bash -lc '
cd /opt/genestack
source scripts/lib/hyperconverged-common.sh
writeMetalLBConfig "'"${METAL_LB_EXTERNAL_IP}"'" \
  "/etc/genestack/manifests/metallb/metallb-openstack-service-lb.yml" \
  "'"${METAL_LB_INTERNAL_IP}"'"
'

sudo kubectl apply -f /etc/genestack/manifests/metallb/metallb-openstack-service-lb.yml
kubectl get ipaddresspool,l2advertisement -n metallb-system
```

### 3. Generate the Gateway Config

Use the interactive helper to classify the current routes:

``` shell
sudo /opt/genestack/scripts/generate-envoy-gateway-config.sh \
  --domain example.com \
  --output /etc/genestack/envoy-gateways.yaml
```

For external Let's Encrypt certificates:

``` shell
sudo /opt/genestack/scripts/generate-envoy-gateway-config.sh \
  --domain example.com \
  --acme-email cloud@example.com \
  --output /etc/genestack/envoy-gateways.yaml
```

The helper shows each current `HTTPRoute` and asks whether it should be
internal, external, both, or skipped. Routes without service backends, such as
HTTP redirect routes, default to skipped.

Review the generated file:

``` shell
sudo less /etc/genestack/envoy-gateways.yaml
```

Confirm:

- The external gateway uses `gateway-api-external`.
- The internal gateway uses `gateway-api-internal`.
- The external gateway class is `external-eg`.
- The internal gateway class is `internal-eg`.
- The route exposure decisions are correct.
- ACME is enabled only when desired.

### 4. Cut Over

Run the install script with the config file:

``` shell
sudo /opt/genestack/bin/install-envoy-gateway.sh \
  --config /etc/genestack/envoy-gateways.yaml
```

This updates the Envoy Helm release to config mode, waits for the controller,
deletes the legacy `flex-gateway`, creates the configured gateways, and applies
the configured routes.

### 5. Validate

``` shell
kubectl get gateway -A -o wide
kubectl get gatewayclass
kubectl get httproute -A -o wide
kubectl get svc -n envoyproxy-gateway-system
kubectl get certificate -n envoy-gateway
kubectl get orders,challenges -A
```

Test representative external and internal routes:

``` shell
curl -vk --resolve keystone.example.com:443:<external-vip> \
  https://keystone.example.com/v3

curl -vk --resolve prometheus.internal.example.com:443:<internal-vip> \
  https://prometheus.internal.example.com/
```

### 6. Clean Up Legacy HTTPRoutes

After the new suffixed routes are accepted and traffic tests pass, remove only
the pre-cutover routes that still reference the legacy gateway.

Dry run:

``` shell
sudo /opt/genestack/scripts/cleanup-envoy-httproutes.sh cleanup \
  --snapshot /etc/genestack/envoy-httproutes-before-cutover.json
```

Execute:

``` shell
sudo /opt/genestack/scripts/cleanup-envoy-httproutes.sh cleanup \
  --snapshot /etc/genestack/envoy-httproutes-before-cutover.json \
  --execute
```

## Convert a Bare Metal Deployment

Bare metal conversion follows the same Kubernetes workflow as the lab, but
network preparation is a real infrastructure task. No lab script creates or
reserves the second VIP for you.

### 1. Plan VIPs, DNS, and Reachability

Before touching Envoy, decide:

- External gateway VIP.
- Internal gateway VIP.
- Whether MetalLB uses L2 or BGP advertisements in this environment.
- Which VLAN, subnet, or routed domain should receive the internal VIP.
- Which DNS zones resolve external and internal names.
- Whether external routes use Let's Encrypt or an existing internal issuer.

Typical DNS shape:

``` text
*.example.com            A or CNAME -> external VIP
*.internal.example.com   A or CNAME -> internal VIP
```

For Let's Encrypt HTTP01, public DNS and firewall policy must allow the ACME
service to reach the external gateway on port 80.

### 2. Capture the Current State

``` shell
kubectl get gateway,gatewayclass,httproute,certificate -A -o wide
kubectl get svc -n envoyproxy-gateway-system
kubectl get ipaddresspool,l2advertisement -n metallb-system

sudo /opt/genestack/scripts/cleanup-envoy-httproutes.sh snapshot \
  --output /etc/genestack/envoy-httproutes-before-cutover.json \
  --force
```

### 3. Prepare MetalLB Address Pools

Create or update MetalLB resources for the two gateway VIPs. The exact
advertisement object depends on the site network design. This example uses L2
advertisements:

``` yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: gateway-api-external
  namespace: metallb-system
spec:
  addresses:
    - <external-vip>/32
  autoAssign: false
---
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: gateway-api-internal
  namespace: metallb-system
spec:
  addresses:
    - <internal-vip>/32
  autoAssign: false
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: openstack-external-advertisement
  namespace: metallb-system
spec:
  ipAddressPools:
    - gateway-api-external
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: openstack-internal-advertisement
  namespace: metallb-system
spec:
  ipAddressPools:
    - gateway-api-internal
```

Apply and validate:

``` shell
kubectl apply -f metallb-envoy-gateway-pools.yaml
kubectl get ipaddresspool,l2advertisement -n metallb-system
```

Make sure upstream switches, firewalls, BGP peers, and routing policy permit
the intended clients to reach each VIP.

### 4. Generate the Gateway Config

Use the current live routes as input:

``` shell
sudo /opt/genestack/scripts/generate-envoy-gateway-config.sh \
  --domain example.com \
  --output /etc/genestack/envoy-gateways.yaml
```

With external Let's Encrypt:

``` shell
sudo /opt/genestack/scripts/generate-envoy-gateway-config.sh \
  --domain example.com \
  --acme-email cloud@example.com \
  --output /etc/genestack/envoy-gateways.yaml
```

For a non-interactive review workflow, capture the routes first and generate a
candidate file outside `/etc/genestack`:

``` shell
kubectl get httproute -A -o json > /tmp/httproutes-before-cutover.json

/opt/genestack/scripts/generate-envoy-gateway-config.sh \
  --routes-file /tmp/httproutes-before-cutover.json \
  --domain example.com \
  --output /tmp/envoy-gateways.yaml
```

Review and then copy the approved file into place.

### 5. Cut Over

Schedule a maintenance window if the current gateway serves production traffic.
Then run:

``` shell
sudo /opt/genestack/bin/install-envoy-gateway.sh \
  --config /etc/genestack/envoy-gateways.yaml
```

Expected results:

- The Envoy Helm release uses the config-mode post-renderer.
- `flex-gateway` is removed.
- `external` and `internal` gateways are created if enabled.
- Each gateway receives the configured GatewayClass.
- Routes are rendered according to exposure.

### 6. Validate

``` shell
kubectl get gateway -A -o wide
kubectl get gatewayclass
kubectl get httproute -A -o wide
kubectl get svc -n envoyproxy-gateway-system
kubectl get certificate -n envoy-gateway
kubectl get orders,challenges -A
```

Confirm the Envoy data-plane services received the intended VIPs:

``` shell
kubectl get svc -n envoyproxy-gateway-system -o wide
```

Test from the correct client networks:

``` shell
curl -vk --resolve keystone.example.com:443:<external-vip> \
  https://keystone.example.com/v3

curl -vk --resolve prometheus.internal.example.com:443:<internal-vip> \
  https://prometheus.internal.example.com/
```

If ACME is enabled, inspect certificate issuance:

``` shell
kubectl get certificates,certificaterequests,orders,challenges -A
kubectl describe certificate -n envoy-gateway <certificate-name>
```

### 7. Clean Up Legacy HTTPRoutes

Dry run:

``` shell
sudo /opt/genestack/scripts/cleanup-envoy-httproutes.sh cleanup \
  --snapshot /etc/genestack/envoy-httproutes-before-cutover.json
```

Execute after validation:

``` shell
sudo /opt/genestack/scripts/cleanup-envoy-httproutes.sh cleanup \
  --snapshot /etc/genestack/envoy-httproutes-before-cutover.json \
  --execute
```

## Operational Notes

### Rollback

Rollback depends on how far the cutover progressed. At minimum, keep these
artifacts:

- `/etc/genestack/envoy-httproutes-before-cutover.json`
- `/etc/genestack/envoy-gateways.yaml`
- The previous MetalLB manifest or address pool definitions.
- The command output from the preflight `kubectl get` commands.

If the new gateways fail before legacy route cleanup, the old HTTPRoutes still
exist but may reference the deleted `flex-gateway`. Restoring the legacy mode
requires reinstalling Envoy without `--config` and rerunning the original setup
flow for the deployment domain:

``` shell
sudo /opt/genestack/bin/install-envoy-gateway.sh
sudo /opt/genestack/bin/setup-envoy-gateway.sh \
  --domain example.com
```

If the legacy routes were already deleted, recreate them from source control or
from the pre-cutover route snapshot before restoring traffic.

### Downtime Expectations

There is a brief interruption when `flex-gateway` is deleted and the new data
plane services receive their VIPs. The exact duration depends on:

- Envoy Gateway controller responsiveness.
- MetalLB advertisement convergence.
- DNS cache behavior.
- Certificate issuance if routes depend on new ACME certificates.
- Client retry behavior.

For the lowest risk conversion, pre-create MetalLB pools and DNS, generate and
review the config file before the window, and run route cleanup only after
traffic validation passes.

### Common Checks

``` shell
kubectl describe gateway -n envoy-gateway external
kubectl describe gateway -n envoy-gateway internal
kubectl describe httproute -A
kubectl logs -n envoyproxy-gateway-system deployment/envoy-gateway
kubectl get events -A --sort-by=.lastTimestamp
```

Route status should show `Accepted=True` and `ResolvedRefs=True` for the new
parent gateway. If a route is accepted but returns 404, confirm the hostname,
listener `sectionName`, and backend service/port match the intended route.
