# Secret management

Genestack service passwords and chart-derived Kubernetes secrets are managed by the
individual `/opt/genestack/bin/install-*.sh` scripts.

Each service installer reads its schema from `/opt/genestack/bin/services/*.yaml`,
creates missing secrets before Helm runs, and reuses existing Kubernetes secret
values on later runs. Kubernetes is the source of truth for existing secret data;
installers must not replace an existing password or key just because the chart
version changed.

Secret creation, patching, and Helm value collection are expected to fail closed.
If an installer cannot read Kubernetes, create a missing secret, patch a missing
secret key, or build the secret-backed Helm arguments, the install must stop
before Helm can fall back to chart defaults.

Use the secret schema tooling when chart versions change:

``` shell
cd /opt/genestack
.venv/bin/python ops-tools/secret_schema_validator/secret_schema_validator.py
.venv/bin/python ops-tools/default_password_detector/default_password_detector.py
```

## Secret creators outside service install scripts

Most new service secrets belong in `bin/services/*.yaml` and the matching
`bin/install-*.sh` workflow. The following paths are intentional exceptions
because they manage operator-supplied credentials, file-backed config, or
operational mutations rather than chart-derived service passwords.

| Path | Secret scope | Why it is outside the service password schema |
| --- | --- | --- |
| `bin/setup-envoy-gateway.sh` | DNS provider and certificate automation credentials such as Cloudflare, Route53, Azure DNS, Google Cloud DNS, DigitalOcean, ACME DNS, RFC2136, GoDaddy, and Rackspace webhook secrets. | These values are supplied by the operator or provider account and are not OpenStack Helm chart defaults. |
| `bin/setup-monitoring-rgw-storage.sh` | RGW monitoring object-storage credentials. | These values come from the monitoring storage setup, not an OpenStack service chart. |
| `scripts/import-external-cluster.sh` | Imported Rook/Ceph, CSI, and RGW admin integration secrets. | These values are imported from an external Ceph environment and must reflect that cluster. |
| `bin/install-keystone.sh` | `keystone-shibd-etc`, sourced from `/etc/genestack/keystone-sp/shibboleth/`. | This is file-backed Shibboleth configuration that the Keystone installer syncs when federation is enabled. |
| `bin/install-qonos.sh` | `qonos-etc`, sourced from a rendered `qonos.conf`. | This is file-backed service configuration derived from managed secret values. |
| `bin/install-kube-ovn.sh` | `kube-ovn-tls`. | This is infrastructure TLS material for Kube-OVN, not an OpenStack service password. |
| `ansible/roles/manila_enablement_techpreview/tasks/manila_k8s_secrets.yml` | Manila tech preview secrets and SSH key material. | The role calls the shared service secret helper, then performs explicit tech preview key handling for that workflow. |
| `ansible/roles/trove_enablement_techpreview/tasks/trove_k8s_secrets.yml` | Trove tech preview secrets and SSH key material. | The role calls the shared service secret helper, then performs explicit tech preview key handling for that workflow. |
| `scripts/rotate-openstack-admin-secret-passwords.sh` | Existing OpenStack admin password secrets. | This is an explicit rotation tool that mutates existing secrets after deployment. |
| `scripts/edit-clouds-yaml-secret.sh` | `clouds-yaml-secret`. | This is an operator utility for editing an existing OpenStack client configuration secret. |

When adding any new secret creator outside an install script, keep the same
operational rules:

* Document it in the table above.
* Only keep it outside `bin/services/*.yaml` when the secret is not a chart-derived
  service credential.
* Reuse existing Kubernetes values unless the operator explicitly requested
  rotation or replacement.
* Stop on `kubectl` read, create, patch, or apply failures.
* Clean up temporary files on both success and failure.
