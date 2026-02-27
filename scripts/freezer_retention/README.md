# Freezer Backup Retention Policy Instructions

## Overview

The script helps you automatically set object expiration and/or clean up empty containers after all objects have expired and been deleted.

###### NOTE: This script has only been tested w.r.t Freezer backup containers that are created in swift. But this should work with any other swift containers and objects.

### Prerequisites

```bash
# Install Python Swift client
pip install python-swiftclient

# Source OpenStack credentials of your Flex cluster
source ~/openrc

# Verify access
swift list
```

### Make Scripts Executable

```bash
chmod +x swift_retention_policy.py
```

##### `swift_retention_policy.py`

Complete workflow that sets expiration AND monitors/deletes containers.

**Features:**
- Set X-Delete-At on all objects in containers
- Monitor containers until empty
- Automatically delete empty containers
- Single command for complete cleanup
- Progress tracking
- Timeout protection

**Usage:**

```bash
# Set 5-minute expiration and auto-cleanup
./swift_retention_policy.py -c freezer-bkp-lvm -m 5 --cleanup

# Multiple containers with 1-hour expiration
./swift_retention_policy.py -c freezer-daily -c freezer-weekly -H 1 --cleanup

# Set expiration only (no cleanup)
./swift_retention_policy.py -c freezer-bkp-lvm -d 7

# Custom monitoring interval (check every 30 seconds)
./swift_retention_policy.py -c freezer-bkp-lvm -m 5 --cleanup --check-interval 30

# Set max wait time (give up after 1 hour)
./swift_retention_policy.py -c freezer-bkp-lvm -m 5 --cleanup --max-wait 3600

# Dry run
./swift_retention_policy.py -c freezer-bkp-lvm -m 5 --cleanup --dry-run
```

**Options:**

```
Time Options:
-s, --seconds N           Delete after N seconds
-m, --minutes N           Delete after N minutes
-H, --hours N             Delete after N hours
-d, --days N              Delete after N days
-M, --months N            Delete after N months
-t, --delete-at UNIX      Delete at specific timestamp

Cleanup Options:
--cleanup                 Monitor and delete containers when empty
--check-interval SECONDS  Seconds between checks (default: 60)
--max-wait SECONDS        Maximum time to wait (default: 3600)

Other Options:
--dry-run                 Show what would be done
-v, --verbose             Verbose output
```

---

## Workflow Examples

### Example 1: Quick Cleanup (5 minutes)

Set expiration to 5 minutes and automatically delete container when empty:

```bash
./swift_retention_policy.py -c freezer-bkp-lvm -m 5 --cleanup --check-interval 30
```

**Output:**
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
✓ Connected

======================================================================
PHASE 1: Setting Expiration on Objects
======================================================================

======================================================================
Setting expiration on container: freezer-bkp-lvm
======================================================================
Found 16 objects

✓ Expiration set on 16 objects

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
This may take a while depending on:
  - Expiration time: 5 minute(s)
  - Swift object-expirer interval (typically 5-15 minutes)

[15:30:15] Check #1 (elapsed: 0s)
----------------------------------------------------------------------
⏳ freezer-bkp-lvm: 16 objects remaining

Waiting 30 seconds before next check...
Containers remaining: 1

[15:30:45] Check #2 (elapsed: 30s)
----------------------------------------------------------------------
⏳ freezer-bkp-lvm: 16 objects remaining

...

[15:36:15] Check #13 (elapsed: 360s)
----------------------------------------------------------------------
✓ freezer-bkp-lvm: Empty - deleting...
  ✓ Container deleted successfully

======================================================================
Phase 2 Summary
======================================================================
Containers deleted: 1
  ✓ freezer-bkp-lvm
======================================================================

✓ Workflow complete
```
---

## Container Status Types

The scripts identify different container states:

| Status | Description | Can Delete? |
|--------|-------------|-------------|
| `empty` | Container has no objects | ✓ Yes |
| `not_found` | Container doesn't exist | N/A |
| `has_permanent_objects` | Has objects without X-Delete-At | ✗ No |
| `waiting_for_expiration` | Objects not yet expired | ✗ No |
| `waiting_for_expirer` | Objects expired but not deleted yet | ✗ No |

---

## Best Practices

### 1. Test with Short Expiration First

```bash
# Test with 1 minute expiration
./swift_retention_policy.py -c test-container -m 1 --cleanup --check-interval 15
```

### 2. Use Dry Run

```bash
# See what would happen without making changes
./swift_retention_policy.py -c freezer-bkp-lvm -m 5 --cleanup --dry-run
```

### 3. Set Reasonable Check Intervals

- **Short expiration (< 10 min)**: Check every 30-60 seconds
- **Medium expiration (1-24 hours)**: Check every 5-15 minutes
- **Long expiration (> 1 day)**: Check every 30-60 minutes

```bash
# For 5-minute expiration
./swift_retention_policy.py -c container -m 5 --cleanup --check-interval 30

# For 1-day expiration
./swift_retention_policy.py -c container -d 1 --cleanup --check-interval 1800
```

### 4. Set Max Wait Time

Prevent scripts from running forever:

```bash
# Give up after 1 hour
./swift_retention_policy.py -c container -m 5 --cleanup --max-wait 3600
```

---

## Troubleshooting

### Container Not Being Deleted

**Problem:** Container shows as empty but won't delete

**Solutions:**

1. **Check for hidden objects:**
   ```bash
   swift list freezer-bkp-lvm --prefix ""
   ```

2. **Manual deletion:**
   ```bash
   swift delete freezer-bkp-lvm
   ```

### Objects Not Expiring

**Problem:** Objects have X-Delete-At but aren't being deleted

**Solution:** Check swift-object-expirer daemon

### Script Times Out

**Problem:** Script reaches max-wait before container is empty

**Solutions:**

1. **Increase max-wait:**
   ```bash
   ./swift_retention_policy.py -c container -m 5 --cleanup --max-wait 7200
   ```
---
