# Freezer Vendor Data Setup

## Overview

When freezer is enabled in a region, the freezer-scheduler is automatically
installed on every new VM at first boot via Nova vendor_data. This enables
backup and restore for all supported backup types (VM snapshot, Cinder volume,
local filesystem, MySQL, MongoDB) via Skyline UI without any manual agent
installation on VMs.

## How It Works

When freezer is deployed via Genestack (`freezer: true` in
`openstack-components.yaml`), a post-deploy K8s Job
(`freezer-vendordata-inject`) automatically:

1. Reads the freezer service password from the
   `freezer-keystone-user` K8s Secret
2. Reads the existing `static-vendor-data` ConfigMap content
3. Appends the freezer cloud-init script to the existing content
4. Patches the ConfigMap back with the merged content

This ensures any existing vendor_data content (e.g., VMM or other services)
is preserved. The freezer content is appended, never overwrites.

No manual steps are required. No operator intervention needed.

## Automatic Behavior

```
freezer: true in openstack-components.yaml
    → Genestack deploys freezer-api and inject job
    → Inject job appends freezer cloud-init to vendor_data ConfigMap
    → Nova metadata serves merged content to all new VMs
    → Every new VM gets freezer agent + scheduler at first boot
    → Scheduler registers VM with freezer-api
    → VM ready for backup via Skyline UI
```

## What the Cloud-init Script Does

On every new VM at first boot, cloud-init runs the appended script which:

1. Checks if freezer is already installed (idempotent, skips if yes)
2. Installs required system packages (python3-dev, python3-venv, git)
3. Creates a Python virtual environment at `/opt/freezer-venv`
4. Installs freezer from the OpenStack master branch
5. Writes `/etc/freezer/freezer-scheduler.conf` with Keystone credentials
6. Writes `/etc/freezer/openrc` for systemd environment
7. Creates and starts a `freezer-scheduler` systemd service
8. The scheduler registers the VM as a client in freezer-api

## Verification

After creating a new VM, verify installation:

```bash
# Check console log for success message
openstack console log show <vm-name> | grep "Freezer scheduler installed"
```

Or SSH into the VM:

```bash
# Service status
systemctl status freezer-scheduler

# Binaries installed
ls -la /opt/freezer-venv/bin/ | grep freezer

# Scheduler logs
journalctl -u freezer-scheduler -n 30 --no-pager
```

## Coexistence With Other Vendor Data

The inject job reads the existing `static-vendor-data` ConfigMap before
making changes. It appends the freezer cloud-init content to whatever is
already present. This ensures coexistence with any other service that uses
the same ConfigMap (e.g., services deployed via the overrides repo).

The job is idempotent — if freezer content is already present in the
ConfigMap, it skips the append.

## Disabling

If freezer is disabled in a region, the inject job is not deployed. Existing
vendor_data content from other services remains untouched. No cleanup needed.

## Notes

- Existing VMs are not affected. Only new VMs created after freezer is
  enabled will have freezer auto-installed.
- The scheduler auto-discovers the region from Keystone's service catalog.
  No `OS_REGION_NAME` is hardcoded.
- The freezer service password is never committed to the repo. It exists
  only at runtime in the K8s Secret and is injected into the ConfigMap by
  the job.
- After first freezer deployment, Nova metadata pods need a restart to
  pick up the updated vendor_data ConfigMap:
  ```bash
  kubectl rollout restart deployment nova-api-metadata -n openstack
  ```
  Subsequent freezer upgrades that re-run the inject job will also require
  this step if the content changes.
