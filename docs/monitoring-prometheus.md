# Prometheus

Genestack uses the `kube-prometheus-stack` chart to deploy Prometheus, Alertmanager, node-exporter, and kube-state-metrics into the `monitoring` namespace.

## Paths

- Base Helm values: `/opt/genestack/base-helm-configs/kube-prometheus-stack/`
- Service overrides: `/etc/genestack/helm-configs/kube-prometheus-stack/`
- Kustomize overlay: `/etc/genestack/kustomize/kube-prometheus-stack/overlay/`

## Install

```shell
/opt/genestack/bin/install-kube-prometheus-stack.sh
```

## Verify

```shell
kubectl -n monitoring get pods -l app.kubernetes.io/instance=kube-prometheus-stack
kubectl -n monitoring get prometheus,alertmanager
```

## Alertmanager Configuration

The base Alertmanager example is stored at:

- `/opt/genestack/base-helm-configs/kube-prometheus-stack/alertmanager_config.yaml`

If you want to customize Alertmanager, place your override file in:

- `/etc/genestack/helm-configs/kube-prometheus-stack/`

Example:

```shell
read -p "webhook_url: " webhook_url
sed -i -e "s#https://webhook_url.example#${webhook_url}#" \
  /etc/genestack/helm-configs/kube-prometheus-stack/alertmanager_config.yaml
```

Any additional YAML files placed in `/etc/genestack/helm-configs/kube-prometheus-stack/` are included by the install script, so this is also the supported place for custom Prometheus rules.

!!! info "Talos-only"

    Prometheus node-exporter needs privileged host access on Talos.
    Skip this on Kubespray unless your cluster enforces the same restriction.
