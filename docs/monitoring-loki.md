# Loki

Loki is Genestack's log backend. It is deployed into the `monitoring` namespace and follows the same override layout as the rest of Genestack.

## Paths

- Base Helm values: `/opt/genestack/base-helm-configs/loki/`
- Service overrides: `/etc/genestack/helm-configs/loki/`
- Kustomize overlay: `/etc/genestack/kustomize/loki/overlay/`

## Default Behavior

The default base file, `/opt/genestack/base-helm-configs/loki/loki-helm-overrides.yaml`, uses a single-binary Loki deployment with filesystem-backed storage. This is the supported default for simple environments and first-pass validation.

## Storage Backends

Add one or more override files to `/etc/genestack/helm-configs/loki/` before installing Loki.

### Swift

Example file:

- `/opt/genestack/base-helm-configs/loki/loki-helm-swift-overrides.yaml.example`

### Generic S3-Compatible

Example file:

- `/opt/genestack/base-helm-configs/loki/loki-helm-s3-overrides.yaml.example`

### Rook/Ceph RGW

Example file:

- `/opt/genestack/base-helm-configs/loki/loki-helm-rook-rgw-overrides.yaml.example`

If you are using a Rook RGW object store, you can generate the Loki and Tempo override files automatically:

```shell
/opt/genestack/bin/setup-monitoring-rgw-storage.sh
```

This helper uses `mc` (the MinIO Client) for bucket creation. If `mc` is missing, the script downloads a temporary copy. In restricted environments, install `mc` first or allow HTTPS access to `dl.min.io`.

### MinIO

Example file:

- `/opt/genestack/base-helm-configs/loki/loki-helm-minio-overrides.yaml.example`

## Install

```shell
/opt/genestack/bin/install-loki.sh
```

## Verify

```shell
kubectl -n monitoring get pods -l app.kubernetes.io/instance=loki
kubectl -n monitoring port-forward svc/loki-gateway 3100:80
curl http://127.0.0.1:3100/ready
```

!!! info "Talos-only"

    Loki itself does not require the same host access as the collectors, but many environments label the `monitoring` namespace once and reuse it for the whole stack.
    Skip this on Kubespray unless your cluster enforces the same restriction.
