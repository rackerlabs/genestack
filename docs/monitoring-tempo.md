# Tempo

Tempo is Genestack's distributed tracing backend. It is deployed into the `monitoring` namespace.

## Paths

- Base Helm values: `/opt/genestack/base-helm-configs/tempo/`
- Service overrides: `/etc/genestack/helm-configs/tempo/`
- Kustomize overlay: `/etc/genestack/kustomize/tempo/overlay/`

## Default Behavior

The default base file, `/opt/genestack/base-helm-configs/tempo/tempo-helm-overrides.yaml`, uses PVC-backed local storage.

## Optional Object Storage

Add an override file to `/etc/genestack/helm-configs/tempo/` before installation if you want object storage.

Available examples:

- Generic S3-compatible: `/opt/genestack/base-helm-configs/tempo/tempo-helm-s3-overrides.yaml.example`
- Rook/Ceph RGW: `/opt/genestack/base-helm-configs/tempo/tempo-helm-rook-rgw-overrides.yaml.example`

If you are using Rook RGW, the helper below creates the user, buckets, Kubernetes secret, and override files:

```shell
/opt/genestack/bin/setup-monitoring-rgw-storage.sh
```

This helper uses `mc` (the MinIO Client) for bucket creation. If `mc` is not installed, the script downloads a temporary copy. In restricted environments, install `mc` first or allow HTTPS access to `dl.min.io`.

## Install

```shell
/opt/genestack/bin/install-tempo.sh
```

## Verify

```shell
kubectl -n monitoring get pods -l app.kubernetes.io/instance=tempo
kubectl -n monitoring port-forward svc/tempo 3200:3200
curl http://127.0.0.1:3200/ready
```
