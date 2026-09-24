# :material-snowflake: Freezer Backup via Skyline

This document covers using the Skyline dashboard to create, schedule, and restore
Freezer backups, and provides an operational guide for troubleshooting common issues.

Freezer backup functionality in Skyline is available when the `freezer` endpoint is
registered in the OpenStack service catalog. All Backup & Restore menu items and
instance-level backup options are hidden automatically when the service is not present.

---

## :material-book-open-variant: User Guide

### Prerequisites

- Freezer API deployed and registered in the service catalog
  (see [Deploy Freezer](openstack-freezer.md)).
- A Swift container exists or will be created at job time (Skyline creates it
  automatically if you type a new name in the container field).
- The VM you want to back up must have the Freezer agent and scheduler installed.

---

### :material-plus-circle: Enable Backup at Instance Create Time

The easiest way to install the agent is to enable backup when launching a new instance.

1. Navigate to **Compute → Instances → Create Instance**.
2. In the **System** step, find the **Enable Backup** checkbox (visible by default when
   Freezer is available — no need to expand Advanced Options).
3. Tick **Enable Backup**.
4. Enter your **Backup Password** (your OpenStack account password).
   This is embedded in the instance cloud-init data so the on-VM scheduler can
   authenticate to the backup service. It is not stored by Skyline.
5. Complete the rest of the wizard and launch the instance.

On first boot, cloud-init automatically installs `freezer-agent` and
`freezer-scheduler` inside `/opt/freezer-venv` and starts the scheduler as a
systemd service.

!!! note
    This method only works for instances **created through Skyline**. For existing VMs,
    install the agent manually — see [Manual Agent Install](#manual-agent-install-existing-vms) below.

---

### :material-download: Manual Agent Install (Existing VMs)

SSH into the VM and run:

```bash
sudo apt-get install -y python3-venv python3-dev build-essential git libssl-dev

python3 -m venv /opt/freezer-venv
source /opt/freezer-venv/bin/activate

pip install "git+https://opendev.org/openstack/freezer.git@master"
pip install "git+https://opendev.org/openstack/python-freezerclient.git@master"

sudo mkdir -p /etc/freezer /var/log/freezer
```

Write the scheduler config at `/etc/freezer/freezer-scheduler.conf`:

```ini
[DEFAULT]
log_file = /var/log/freezer/scheduler.log

[service_auth]
auth_url = <keystone-url>
username = <your-username>
password = <your-password>
user_domain_name = <your-user-domain>
project_id = <your-project-id>
project_domain_name = <your-project-domain>
identity_api_version = 3
auth_type = password
```

Create the systemd unit at `/etc/systemd/system/freezer-scheduler.service`:

```ini
[Unit]
Description=Freezer Scheduler
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment="OS_AUTH_URL=<keystone-url>"
Environment="OS_USERNAME=<your-username>"
Environment="OS_PASSWORD=<your-password>"
Environment="OS_USER_DOMAIN_NAME=<your-user-domain>"
Environment="OS_PROJECT_DOMAIN_NAME=<your-project-domain>"
Environment="OS_PROJECT_ID=<your-project-id>"
Environment="OS_IDENTITY_API_VERSION=3"
Environment="OS_ENDPOINT_TYPE=publicURL"
Environment="PYTHONWARNINGS=ignore::DeprecationWarning"
ExecStart=/opt/freezer-venv/bin/freezer-scheduler \
    --config-file /etc/freezer/freezer-scheduler.conf \
    --no-daemon start
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable freezer-scheduler
sudo systemctl start freezer-scheduler
```

!!! warning "Federated / SSO users"
    The on-VM scheduler uses username/password auth against Keystone.
    Federated or SSO users cannot use password auth and will get 401 errors.
    Use a Keystone-local user for the backup scheduler identity.

---

### :material-backup-restore: Create a Backup Job

1. Navigate to **Backup & Restore → Jobs → Create Job**.
2. Fill in the form:

| Field | Description |
|---|---|
| **Job Name** | A unique label for this job |
| **Client (VM)** | The registered VM whose scheduler will run the job |
| **Backup Name** | Name for the backup set (spaces replaced with `_`) |
| **Action Type** | `Backup` or `Restore` |
| **Backup Mode** | See table below |
| **Swift Container** | Pick existing or type a new name — created automatically |
| **Schedule Start Date** | When to first run (blank = run immediately) |
| **Schedule Interval** | Repeat interval e.g. `24 hours`, `7 days` (blank = one-time) |
| **Schedule End Date** | When to stop repeating (optional) |
| **Remove Older Than (days)** | Retention policy — prune backups older than this many days on each run. Decimals allowed (e.g. `0.5` = 12 hours). Blank = keep all |
| **Max Retries** | Retry count on failure (default 0) |

**Backup modes:**

| Mode | What it backs up | Extra fields |
|---|---|---|
| `fs` | Files/directories on the VM | Path to Backup |
| `nova` | VM snapshot (via Nova) | Nova Instance UUID |
| `cinder` | Cinder volume | Cinder Volume UUID |
| `mysql` | MySQL database via dump | MySQL Config File, Temp Backup Path |
| `mongo` | MongoDB via LVM snapshot | LVM Source Volume, Volume Group, Snapshot Size, Mount Path |

3. Click **Create Job**. The scheduler on the target VM picks it up within 60 seconds.

---

### :material-broom: Backup Retention

Set **Remove Older Than (days)** on a job to automatically prune old backups. On
each run, backups in the container older than the given age are deleted. Decimals
are allowed for sub-day windows (e.g. `0.5` = 12 hours). Leave it blank to keep
all backups.

!!! warning "Retention only applies to scheduled (recurring) jobs"
    Pruning happens **when a job runs**, and a run never deletes the backup it
    just created (it is not old enough yet). So retention takes effect only on
    **recurring** jobs — each run prunes backups that earlier runs created once
    they cross the age threshold. A **one-time** job will not prune its own
    backup, and in a fresh container it deletes nothing. Set a **Schedule
    Interval** for retention to be meaningful.

!!! note "The container is not deleted"
    Retention removes backup objects, not the Swift container. An emptied
    container is kept for the next backup cycle. To remove the container itself,
    delete it manually from Object Storage once you no longer need the backup
    target.

---

### :material-restore: Restore a Backup

1. Navigate to **Backup & Restore → Backups**.
2. Find the backup and click **Restore**.
3. Select the **Client (VM)** that will perform the restore.
4. Depending on the backup mode:
   - **fs / mysql / mongo**: enter a **Restore Path** (defaults to the original path).
   - **nova**: select a **Network** — the VM is restored as a new instance on that network.
   - **cinder**: no extra input — restores directly to the volume.
5. Click **Restore**. The job appears as `scheduled` and transitions to `running → completed`
   within one scheduler poll cycle (~60s).

!!! tip
    If the restore stays `scheduled` indefinitely, the scheduler on the target VM
    is likely stopped. See [Common Issues](#common-issues) below.

---

### :material-pause-circle: Disable / Resume Backup

- **Disable Backup** (on the Instance row) — pauses all scheduled jobs for that VM.
  Existing backups in Swift are kept. The agent stays installed.
- **Enable Backup** (same row, after disabling) — resumes scheduled jobs.
  No reinstall needed, no password required.

---

## :material-wrench: Operational Guide

### Checking Scheduler Health

```bash
# Is the scheduler running?
sudo systemctl status freezer-scheduler

# Live log
sudo tail -f /var/log/freezer/scheduler.log

# Healthy output — polls every 60s
# INFO freezer.scheduler.freezer_scheduler [-] Polling for jobs from API
# INFO freezer.scheduler.utils [-] Fetched N jobs from API
```

---

### Common Issues

#### Restore / job stuck at `scheduled`

The scheduler is not polling. Check on the target VM:

```bash
sudo systemctl status freezer-scheduler
sudo journalctl -u freezer-scheduler -n 50 --no-pager
```

Start it if stopped:

```bash
sudo systemctl start freezer-scheduler
```

#### Scheduler shows `Fetched 0 jobs` but job exists in Skyline

The job's `client_id` does not match the scheduler's registered client. The `client_id`
is the VM's instance name set at enable time. Verify:

```bash
sudo grep client_id /etc/freezer/freezer-scheduler.conf
```

Compare with the **Client (VM)** field on the job in Skyline → Jobs.

#### 401 Unauthorized in scheduler log

```
keystoneauth1.exceptions.http.Unauthorized: The request you have made requires authentication.
```

Causes:
- Wrong password in the scheduler config / systemd environment.
- Federated/SSO user — password auth is not supported; use a Keystone-local user.
- Token expired and not refreshed (scheduler should auto-retry on restart).

Fix: update the password in `/etc/freezer/freezer-scheduler.conf` and the systemd
unit, then restart:

```bash
sudo systemctl daemon-reload
sudo systemctl restart freezer-scheduler
```

#### Job runs repeatedly instead of once

A job without a `schedule_interval` runs once and completes. If a job keeps repeating
every ~60s, it was created with an interval. Delete the job from Skyline → Jobs and
recreate it without a schedule interval.

If the job no longer exists in Skyline but still runs, the scheduler has a stale local
copy. Restart the scheduler:

```bash
sudo systemctl restart freezer-scheduler
```

#### Eventlet DeprecationWarning in scheduler log

```
EventletDeprecationWarning: Eventlet is deprecated...
```

This is **benign log noise** from an oslo_service dependency. It does not affect
backup or restore functionality.

`EventletDeprecationWarning` is not a subclass of `DeprecationWarning`, so a
category-specific filter (or `PYTHONWARNINGS=ignore::DeprecationWarning`) does
**not** suppress it — only a category-agnostic `simplefilter("ignore")` does.
A `sitecustomize.py` in the venv does not work either, because Debian/Ubuntu
ship a system `/usr/lib/pythonX.Y/sitecustomize.py` that shadows it. The
reliable fix is a `.pth` file in the venv site-packages, which the `site`
module always executes at interpreter startup — for both the scheduler and the
agent subprocess it spawns.

VMs created through Skyline get this automatically. For existing VMs, apply it
manually (adjust `python3.12` to the venv's Python version):

```bash
echo 'import warnings; warnings.simplefilter("ignore")' | \
  sudo tee /opt/freezer-venv/lib/python*/site-packages/zzz_suppress_warnings.pth
sudo systemctl restart freezer-scheduler
```

#### freezer-api image compatibility

Freezer backup and restore via Skyline was validated against the
`stable/2025.1-latest` freezer-api image. If the freezer-api pod fails to start
after an image change, check the pod logs and confirm the image is compatible
with the deployed `oslo.middleware` version.

#### Backups present in Skyline but not in Swift (or vice versa)

Freezer-api stores backup metadata separately from the actual data in Swift.
Deleting a backup via Skyline removes the metadata record but does **not** delete
the Swift objects. To free Swift storage, also delete the objects from the container:

```bash
source /opt/freezer-venv/bin/activate

openstack object list <container-name> | grep <backup-name> \
  | awk '{print $2}' | xargs -I{} openstack object delete <container-name> {}
```

---

### Useful Commands (on the VM)

```bash
source /opt/freezer-venv/bin/activate

# List all backups
freezer backup-list

# Delete backups matching a name (bulk)
freezer backup-list | grep '<backup-name>' | awk '{print $2}' \
  | xargs -I{} freezer backup-delete {}

# List all jobs
freezer job-list

# Show a specific job (check schedule block)
freezer job-show <job-id>

# Stop a running job
freezer job-stop <job-id>

# Delete a job
freezer job-delete <job-id>
```
