# `check_octavia_ovn` systemd deployment

This document explains how the `check_octavia_ovn` script is installed, where its files live, how to enable supported features, and how to access logs.

## Installed file locations

When [`install_check_octavia_ovn_systemd.sh`](/Users/chris.breu/code/flex/genestack/ops-tools/check_octavia_ovn/install_check_octavia_ovn_systemd.sh) is run as root, it installs:

- Script: `/usr/local/bin/check_octavia_ovn.sh`
- systemd service: `/etc/systemd/system/check-octavia-ovn.service`
- systemd timer: `/etc/systemd/system/check-octavia-ovn.timer`
- Environment override file: `/etc/default/check-octavia-ovn`
- Timer override file: `/etc/systemd/system/check-octavia-ovn.timer.d/override.conf`
- State directory: `/var/lib/check_octavia_ovn`
- State file: `/var/lib/check_octavia_ovn/failovers.state`

## What the state file does

The state file at `/var/lib/check_octavia_ovn/failovers.state` tracks which load balancers the script has already attempted to fail over.

This preserves failover history across timer runs so the same unhealthy load balancer is not repeatedly failed over every minute. When a load balancer becomes healthy again, its entry is removed from the state file.

## Default runtime behavior under systemd

The timer runs the service once per minute by default.

The service currently starts the script with:

```ini
ExecStart=/usr/local/bin/check_octavia_ovn.sh --apply
```

That means:

- Failover actions are enabled by default under systemd
- Output is sent to `journald`
- File logging is not enabled unless you explicitly configure `LOG_FILE`
- The state file is preserved at `/var/lib/check_octavia_ovn/failovers.state`

## Feature configuration

Edit `/etc/default/check-octavia-ovn` to change runtime settings.

After changing the file, reload systemd and restart the timer:

```bash
sudo systemctl daemon-reload
sudo systemctl restart check-octavia-ovn.timer
```

### Configure parallelism

Set:

```bash
PARALLEL=20
```

This controls the maximum number of concurrent load balancer checks.

### Configure failover retry timing

Set:

```bash
FAILOVER_TIMEOUT=300
```

This is the number of seconds the script waits before it will re-issue a failover for a load balancer that is still unhealthy and already recorded in the state file.

### Configure a custom state file location

Set:

```bash
STATE_FILE=/some/other/path/failovers.state
```

If you do not set this, the default path is `/var/lib/check_octavia_ovn/failovers.state`.

### Enable optional file logging

By default, systemd captures logs in `journald`, so no file log is required.

If you also want a flat file log, set:

```bash
LOG_FILE=/var/log/octavia_ovn_check.log
```

When `LOG_FILE` is set, the script appends to that file and still writes to stdout/stderr, so logs continue to appear in `journald`.

### Enable debug output

Set:

```bash
DEBUG=1
```

This includes raw OVN JSON output in the logs.

### Configure a custom kubectl command

Set:

```bash
KUBECTL_CMD=kubectl
```

Use this if the environment requires a different `kubectl` wrapper or path.

### Configure the timer interval

The run interval is configured with a systemd timer drop-in instead of the environment file.

Edit:

```bash
/etc/systemd/system/check-octavia-ovn.timer.d/override.conf
```

Set the `[Timer]` section to the interval you want. Example for every 5 minutes:

```ini
[Timer]
OnUnitActiveSec=
OnUnitActiveSec=5min
```

The blank `OnUnitActiveSec=` line clears the default before setting the new interval.

After changing the timer override, reload systemd and restart the timer:

```bash
sudo systemctl daemon-reload
sudo systemctl restart check-octavia-ovn.timer
```

You can verify the active timer settings with:

```bash
sudo systemctl cat check-octavia-ovn.timer
sudo systemctl status check-octavia-ovn.timer
```

## Dry-run mode

The script supports dry-run mode:

```bash
/usr/local/bin/check_octavia_ovn.sh --dry-run
```

or:

```bash
DRY_RUN=1 /usr/local/bin/check_octavia_ovn.sh
```

However, the current systemd service uses:

```ini
ExecStart=/usr/local/bin/check_octavia_ovn.sh --apply
```

Because `--apply` is passed directly in the unit file, setting `DRY_RUN=1` in `/etc/default/check-octavia-ovn` will not put the systemd-managed run into dry-run mode.

To make the systemd-managed service run in dry-run mode, you must modify the service definition so `--apply` is removed from `ExecStart`, then control mode via the environment file.

## Accessing logs

### View recent service logs

```bash
sudo journalctl -u check-octavia-ovn.service -n 100 --no-pager
```

### Follow logs live

```bash
sudo journalctl -u check-octavia-ovn.service -f
```

### View timer status

```bash
sudo systemctl status check-octavia-ovn.timer
```

### View service status

```bash
sudo systemctl status check-octavia-ovn.service
```

### View optional file log

Only applicable if `LOG_FILE` is configured:

```bash
sudo tail -f /var/log/octavia_ovn_check.log
```

## Running the service manually

To trigger an immediate run without waiting for the timer:

```bash
sudo systemctl start check-octavia-ovn.service
```

Then inspect the logs:

```bash
sudo journalctl -u check-octavia-ovn.service -n 100 --no-pager
```

## Disable or re-enable the check

To stop future scheduled runs and disable the timer:

```bash
sudo systemctl disable --now check-octavia-ovn.timer
sudo systemctl stop check-octavia-ovn.service
```

To re-enable scheduled runs:

```bash
sudo systemctl enable --now check-octavia-ovn.timer
```

To also trigger an immediate one-off run after re-enabling:

```bash
sudo systemctl start check-octavia-ovn.service
```
