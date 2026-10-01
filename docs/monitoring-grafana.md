# Grafana

Grafana is deployed into the `monitoring` namespace with the upstream Grafana Helm chart.

## Paths

- Base Helm values: `/opt/genestack/base-helm-configs/grafana/`
- Service overrides: `/etc/genestack/helm-configs/grafana/`
- Kustomize overlay: `/etc/genestack/kustomize/grafana/overlay/`

## Secrets

The Grafana installer manages the `grafana-db` Kubernetes Secret idempotently. If the Secret already exists, the installer reuses the existing values. If it is missing, the installer creates it before applying the Helm chart.

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
