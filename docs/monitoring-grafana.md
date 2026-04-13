# Grafana

Grafana is deployed into the `monitoring` namespace with the upstream Grafana Helm chart.

## Paths

- Base Helm values: `/opt/genestack/base-helm-configs/grafana/`
- Service overrides: `/etc/genestack/helm-configs/grafana/`
- Kustomize overlay: `/etc/genestack/kustomize/grafana/overlay/`

## Secrets

The supported way to prepare Grafana secrets is:

```shell
/opt/genestack/bin/create-secrets.sh
```

That workflow generates the `grafana-db` secret in `/etc/genestack/kubesecrets.yaml`. The Grafana installer applies it to the `monitoring` namespace automatically if it is not already present.

Manual secret creation is only needed if you are not using `create-secrets.sh`:

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

```yaml
--8<-- "manifests/grafana/azure-client-secret.yaml"
```

Then add your Azure overrides in:

```yaml
--8<-- "base-helm-configs/grafana/azure-overrides.yaml.example"
```

## Install

```shell
/opt/genestack/bin/install-grafana.sh
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
