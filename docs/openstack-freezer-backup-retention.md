# Freezer Backup Retention Policy

## Overview

The `swift_retention_policy.py` script helps you automatically set object expiration and clean up empty Swift containers after all objects have expired and been deleted.

!!! note
    This script has only been tested with Freezer backup containers created in Swift, but it should work with any Swift containers and objects.

---

## Prerequisites

!!! info "Requirements"
    - Python Swift client installed
    - OpenStack credentials sourced
    - Access to Swift storage verified

```bash
# Install Python Swift client
pip install python-swiftclient

# Source OpenStack credentials of your Flex cluster
source ~/openrc

# Verify access
swift list
```

Make the script executable:

```bash
chmod +x swift_retention_policy.py
```

---

## Features

The script provides a complete workflow for container cleanup:

- Set `X-Delete-At` on all objects in containers
- Monitor containers until empty
- Automatically delete empty containers
- Single command for complete cleanup
- Progress tracking and timeout protection

---

## Usage

### Basic Examples

=== "Quick Cleanup (5 min)"

    ```bash
    ./swift_retention_policy.py -c freezer-bkp-lvm -m 5 --cleanup
    ```

=== "Multiple Containers"

    ```bash
    ./swift_retention_policy.py -c freezer-daily -c freezer-weekly -H 1 --cleanup
    ```

=== "Expiration Only (No Cleanup)"

    ```bash
    ./swift_retention_policy.py -c freezer-bkp-lvm -d 7
    ```

=== "Custom Check Interval"

    ```bash
    ./swift_retention_policy.py -c freezer-bkp-lvm -m 5 --cleanup --check-interval 30
    ```

=== "Dry Run"

    ```bash
    ./swift_retention_policy.py -c freezer-bkp-lvm -m 5 --cleanup --dry-run
    ```

### Command Options

#### Time Options

| Flag | Description |
|------|-------------|
| `-s`, `--seconds N` | Delete after N seconds |
| `-m`, `--minutes N` | Delete after N minutes |
| `-H`, `--hours N` | Delete after N hours |
| `-d`, `--days N` | Delete after N days |
| `-M`, `--months N` | Delete after N months |
| `-t`, `--delete-at UNIX` | Delete at specific Unix timestamp |

#### Cleanup Options

| Flag | Description |
|------|-------------|
| `--cleanup` | Monitor and delete containers when empty |
| `--check-interval SECONDS` | Seconds between checks (default: 60) |
| `--max-wait SECONDS` | Maximum time to wait (default: 3600) |

#### Other Options

| Flag | Description |
|------|-------------|
| `--dry-run` | Show what would be done without making changes |
| `-v`, `--verbose` | Verbose output |

---

## Workflow Example

Set expiration to 5 minutes and automatically delete the container when empty:

```bash
./swift_retention_policy.py -c freezer-bkp-lvm -m 5 --cleanup --check-interval 30
```


??? example "Example Output"

    ```
    ======================================================================
    Swift Container Complete Cleanup Workflow
    ======================================================================

    Containers: freezer-bkp-lvm
    Retention period: 5 minute(s)
    Deletion time: 2026-02-05 15:35:00 (Unix: 1770315300)
    Auto-cleanup: Enabled
    Check interval: 30 seconds
    Max wait time: 3600 seconds

    Connecting to Swift...
    OK Connected

    ======================================================================
    PHASE 1: Setting Expiration on Objects
    ======================================================================

    ======================================================================
    Setting expiration on container: freezer-bkp-lvm
    ======================================================================
    Found 16 objects

    OK Expiration set on 16 objects

    ======================================================================
    Phase 1 Summary
    ======================================================================
    Total objects processed: 16
    Successfully set expiration: 16
    ======================================================================

    ======================================================================
    PHASE 2: Monitoring and Cleanup
    ======================================================================

    Waiting for objects to expire and be deleted...

    [15:30:15] Check #1 (elapsed: 0s)
    ----------------------------------------------------------------------
    WAITING freezer-bkp-lvm: 16 objects remaining

    ...

    [15:36:15] Check #13 (elapsed: 360s)
    ----------------------------------------------------------------------
    OK freezer-bkp-lvm: Empty - deleting...
      OK Container deleted successfully

    ======================================================================
    Phase 2 Summary
    ======================================================================
    Containers deleted: 1
      OK freezer-bkp-lvm
    ======================================================================

    OK Workflow complete
    ```

---

## Container Status Types

| Status | Description | Can Delete? |
|--------|-------------|-------------|
| `empty` | Container has no objects | Yes |
| `not_found` | Container doesn't exist | N/A |
| `has_permanent_objects` | Has objects without `X-Delete-At` | No |
| `waiting_for_expiration` | Objects not yet expired | No |
| `waiting_for_expirer` | Objects expired but not deleted yet | No |

---

## Best Practices

### Test with Short Expiration First

!!! tip
    Always validate with a short expiration before applying to production containers.

```bash
./swift_retention_policy.py -c test-container -m 1 --cleanup --check-interval 15
```

### Use Dry Run

!!! tip
    Preview changes before executing them.

```bash
./swift_retention_policy.py -c freezer-bkp-lvm -m 5 --cleanup --dry-run
```

### Set Reasonable Check Intervals

| Expiration Duration | Recommended Check Interval |
|---------------------|---------------------------|
| < 10 minutes | 30-60 seconds |
| 1-24 hours | 5-15 minutes |
| > 1 day | 30-60 minutes |

=== "Short Expiration"

    ```bash
    ./swift_retention_policy.py -c container -m 5 --cleanup --check-interval 30
    ```

=== "Long Expiration"

    ```bash
    ./swift_retention_policy.py -c container -d 1 --cleanup --check-interval 1800
    ```

### Set Max Wait Time

!!! warning
    Prevent scripts from running indefinitely by setting a max wait time.

```bash
./swift_retention_policy.py -c container -m 5 --cleanup --max-wait 3600
```

---

## Troubleshooting

??? warning "Container Not Being Deleted"
    **Problem:** Container shows as empty but won't delete.

    **Solutions:**

    1. Check for hidden objects:

        ```bash
        swift list freezer-bkp-lvm --prefix ""
        ```

    2. Manual deletion:

        ```bash
        swift delete freezer-bkp-lvm
        ```

??? warning "Objects Not Expiring"
    **Problem:** Objects have `X-Delete-At` set but aren't being deleted.

    **Solution:** Verify the `swift-object-expirer` daemon is running and healthy on the Swift cluster.

??? warning "Script Times Out"
    **Problem:** Script reaches `max-wait` before the container is empty.

    **Solution:** Increase the max wait time:

    ```bash
    ./swift_retention_policy.py -c container -m 5 --cleanup --max-wait 7200
    ```
