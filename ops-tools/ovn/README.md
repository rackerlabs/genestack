# OVN ops tools

`ops-tools/ovn/` contains read-only-by-default diagnostics for comparing
OpenStack Neutron state, Kube-OVN IP CRDs, and the OVN northbound database.
The tools are Python rewrites of the legacy shell scripts that lived under
`scripts/`.

## Tools

| Tool | Purpose | Remediation |
| --- | --- | --- |
| `find_ovn_duplicate_ip.py` | Finds duplicate Kube-OVN IP CRD addresses and reports whether referenced pods still exist. | None |
| `find_ovn_stale_ip_crd.py` | Finds Kube-OVN IP CRDs whose referenced pods no longer exist. | Deletes stale IP CRDs with `--fix --yes-im-really-sure` |
| `ovn_compare_neutron_fips_with_ovn_nat.py` | Compares assigned Neutron floating IPs with OVN `dnat_and_snat` NAT rows. | Deletes stale OVN NAT rows with `--fix --yes-im-really-sure` |
| `ovn_compare_neutron_ports_with_ovn_ports.py` | Compares Neutron ports, excluding floating IP ports, with OVN logical switch ports. | Deletes stale OVN logical switch ports with `--fix --yes-im-really-sure` |
| `ovn_compare_neutron_routers_with_logical_routers.py` | Compares Neutron routers and router ports with OVN logical routers and logical router ports. | Deletes stale OVN logical routers and logical router ports with `--fix --yes-im-really-sure` |
| `ovn_compare_neutron_security_groups_with_acl.py` | Compares Neutron security groups/rules with OVN port groups/ACLs. | Deletes stale OVN port groups and ACLs with `--fix --yes-im-really-sure` |

## Legacy Migration Map

| Legacy script | New script |
| --- | --- |
| `scripts/find-ovn-duplicate-ip.sh` | `ops-tools/ovn/find_ovn_duplicate_ip.py` |
| `scripts/find-ovn-stale-ip-crd.sh` | `ops-tools/ovn/find_ovn_stale_ip_crd.py` |
| `scripts/ovn-compare-neutron-fips-with-ovn-nat.sh` | `ops-tools/ovn/ovn_compare_neutron_fips_with_ovn_nat.py` |
| `scripts/ovn-compare-neutron-ports-with-ovn-ports.sh` | `ops-tools/ovn/ovn_compare_neutron_ports_with_ovn_ports.py` |
| `scripts/ovn-compare-neutron-routers-with-logical-routers.sh` | `ops-tools/ovn/ovn_compare_neutron_routers_with_logical_routers.py` |
| `scripts/ovn-compare-neutron-security-groups-with-acl.sh` | `ops-tools/ovn/ovn_compare_neutron_security_groups_with_acl.py` |

## Requirements

- Python 3.10 or newer.
- `kubectl` configured for the target cluster.
- `kubectl ko nbctl` access for OVN NBDB comparison tools.
- OpenStack CLI credentials for Neutron comparison tools.

## Usage

```bash
./find_ovn_duplicate_ip.py
./find_ovn_stale_ip_crd.py --subnet ovn-default
./ovn_compare_neutron_fips_with_ovn_nat.py --scan
./ovn_compare_neutron_ports_with_ovn_ports.py --format json
./ovn_compare_neutron_routers_with_logical_routers.py --fix --yes-im-really-sure
./ovn_compare_neutron_security_groups_with_acl.py --fix --yes-im-really-sure
```

All tools support:

- `--format text|json`
- `--quiet`
- `--command-timeout <seconds>`

Tools that call external commands also support command overrides:

- `--kubectl-command`
- `--openstack-command`
- `--nbctl-command`

`--scan` is accepted on comparison tools for compatibility with the legacy
shell scripts, but scanning is the default.

## Kubernetes CronJobs

`manifests/` contains one suspended CronJob per OVN Python tool. Each manifest
runs in read-only JSON mode, keeps successful and failed Job history for one
week, and treats exit code `2` as a completed scan with actionable findings.

Before setting `suspend: false`, make sure the target cluster provides the
`ops-tools` service account, RBAC for the required Kubernetes resources,
`kubectl ko nbctl` access, and OpenStack credentials for Neutron comparison
tools.

Install all suspended OVN CronJob manifests:

```bash
kubectl apply -f ops-tools/ovn/manifests/
```

Enable one schedule after the required access is ready:

```bash
kubectl -n openstack patch cronjob ops-tools-ovn-find-duplicate-ip \
  --type merge \
  -p '{"spec":{"suspend":false}}'
```

Enable all OVN schedules:

```bash
for cronjob in $(kubectl -n openstack get cronjobs \
  -l app.kubernetes.io/name=ops-tools \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | grep '^ops-tools-ovn-'); do
  kubectl -n openstack patch cronjob "${cronjob}" \
    --type merge \
    -p '{"spec":{"suspend":false}}'
done
```

Review retained scan logs:

```bash
kubectl -n openstack get jobs -l app.kubernetes.io/name=ops-tools
kubectl -n openstack logs job/<job-name>
```

## Safety

Read-only mode is the default. Any tool that can remove state requires both
`--fix` and `--yes-im-really-sure`.

Fix mode only removes stale resources in the system being scanned. Missing OVN
resources for existing Neutron objects, and IP CRDs with incomplete pod
metadata, remain actionable findings for manual review.

## Exit Codes

- `0`: completed with no actionable findings, or all actionable fixable stale
  resources were remediated successfully.
- `1`: scanner/runtime error.
- `2`: actionable findings remain in read-only mode, or missing/manual-review
  findings remain after fix mode.
- `3`: remediation was attempted and at least one action failed.

## Development

```bash
PYTHONPYCACHEPREFIX=/tmp/genestack-ops-tools-pycache python3 -m py_compile ops-tools/ovn/*.py
PYTHONPYCACHEPREFIX=/tmp/genestack-ops-tools-pycache python3 -m unittest ops-tools/ovn/test_ovn_ops.py
```
