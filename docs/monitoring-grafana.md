# Grafana

Grafana is deployed into the `monitoring` namespace with the upstream Grafana Helm chart.

## Paths

* Base Helm values: `/opt/genestack-observability/helm-configs/grafana/`
* Service overrides: `/etc/genestack/helm-configs/grafana/`
* Kustomize overlay: `/etc/genestack/kustomize/grafana/overlay/`

## Secrets

The Grafana installer ensures the `grafana-db` secret exists in the `monitoring` namespace.

Manual secret creation is normally not required. If you need to pre-provision the secret, use:

```shell
kubectl -n monitoring create secret generic grafana-db \
  --type Opaque \
  --from-literal=password="$(tr -dc _A-Za-z0-9 </dev/urandom | head -c32)" \
  --from-literal=root-password="$(tr -dc _A-Za-z0-9 </dev/urandom | head -c32)" \
  --from-literal=username=grafana
```

## Custom Values

Set `custom_host` in `/etc/genestack/helm-configs/grafana/grafana-helm-overrides.yaml` if you want Grafana exposed by a gateway or ingress:

```yaml
custom_host: grafana.api.example.tld
```

## Azure AD Integration

If you are integrating with Azure AD, apply the client secret in the `monitoring` namespace:

--8<-- "manifests/grafana/azure-client-secret.yaml"

Then add your Azure overrides using the example maintained in the observability repository:

```text
/opt/genestack-observability/helm-configs/grafana/azure-overrides.yaml.example
```

## Install

```shell
/opt/genestack/bin/install-observability.sh grafana
```

## Verify

```shell
kubectl -n monitoring get pods -l app.kubernetes.io/instance=grafana
kubectl -n monitoring port-forward svc/grafana 3000:80
kubectl -n monitoring get secret grafana -o jsonpath='{.data.admin-password}' | base64 -d
```

!!! info "Talos-only"

    The `monitoring` namespace may need privileged Pod Security labels on Talos.
    Skip this on Kubespray unless your cluster enforces the same restriction.
