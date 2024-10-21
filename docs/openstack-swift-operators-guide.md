# Openstack Swift Troubleshooting Guide

## Cluster Health using swift-recon:

```shell
# swift-recon --all
===============================================================================
--> Starting reconnaissance on 4 hosts
===============================================================================
[2016-11-16 15:55:21] Checking async pendings
[async_pending] low: 0, high: 5, avg: 1.2, total: 5, Failed: 0.0%, no_result: 0, reported: 4
===============================================================================
[2016-11-16 15:55:22] Checking auditor stats
[ALL_audit_time_last_path] low: 7169, high: 87084, avg: 57636.2, total: 230544, Failed: 0.0%, no_result: 0, reported: 4
[ALL_quarantined_last_path] low: 0, high: 0, avg: 0.0, total: 0, Failed: 0.0%, no_result: 0, reported: 4
[ALL_errors_last_path] low: 0, high: 0, avg: 0.0, total: 0, Failed: 0.0%, no_result: 0, reported: 4
[ALL_passes_last_path] low: 36583, high: 72002, avg: 62929.5, total: 251718, Failed: 0.0%, no_result: 0, reported: 4
[ALL_bytes_processed_last_path] low: 37109663, high: 73781423, avg: 64161611.5, total: 256646446, Failed: 0.0%, no_result: 0, reported: 4
[ZBF_audit_time_last_path] low: 0, high: 22764, avg: 13134.3, total: 52537, Failed: 0.0%, no_result: 0, reported: 4
[ZBF_quarantined_last_path] low: 0, high: 0, avg: 0.0, total: 0, Failed: 0.0%, no_result: 0, reported: 4
[ZBF_errors_last_path] low: 0, high: 0, avg: 0.0, total: 0, Failed: 0.0%, no_result: 0, reported: 4
[ZBF_bytes_processed_last_path] low: 0, high: 0, avg: 0.0, total: 0, Failed: 0.0%, no_result: 0, reported: 4
=========================================================================== ====
[2016-11-16 15:55:23] Checking updater times
[updater_last_sweep] low: 0, high: 5, avg: 2.2, total: 8, Failed: 0.0%, no_result: 0, reported: 4
=========================================================================== ====
[2016-11-16 15:55:24] Checking on expirers
[object_expiration_pass] low: 0, high: 2, avg: 1.5, total: 5, Failed: 0.0%, no_result: 0, reported: 4
[expired_last_pass] low: 0, high: 0, avg: 0.0, total: 0, Failed: 0.0%, no_result: 0, reported: 4
=========================================================================== ====
[2016-11-16 15:55:24] Checking on replication
[replication_failure] low: 16, high: 33, avg: 22.5, total: 90, Failed: 0.0%, no_result: 0, reported: 4
[replication_success] low: 127, high: 128, avg: 127.5, total: 510, Failed: 0.0%, no_result: 0, reported: 4
[replication_time] low: 0, high: 0, avg: 0.8, total: 3, Failed: 0.0%, no_result: 0, reported: 4
[replication_attempted] low: 128, high: 128, avg: 128.0, total: 512, Failed: 0.0%, no_result: 0, reported: 4
Oldest completion was 2016-11-16 15:54:40 (44 seconds ago) by 10.240.0.61:6000.
Most recent completion was 2016-11-16 15:55:23 (1 seconds ago) by 10.240.0.60:6000.
=========================================================================== ====
[2016-11-16 15:55:24] Getting unmounted drives from 4 hosts...
===============================================================================
[2016-11-16 15:55:24] Checking load averages
[5m_load_avg] low: 0, high: 10, avg: 4.8, total: 19, Failed: 0.0%, no_result: 0, reported: 4
[15m_load_avg] low: 0, high: 10, avg: 4.8, total: 19, Failed: 0.0%, no_result: 0, reported: 4
[1m_load_avg] low: 0, high: 10, avg: 4.9, total: 19, Failed: 0.0%, no_result: 0, reported: 4
===============================================================================
[2016-11-16 15:55:24] Checking disk usage now
Distribution Graph:
 ``0%  4 **********************************
 ``8%  8 *********************************************************************
Disk usage: space used: 29906866176 of 601001820160
Disk usage: space free: 571094953984 of 601001820160
Disk usage: lowest: 0.13%, highest: 8.4%, avg: 4.97616898532%
===============================================================================
[2016-11-16 15:55:25] Checking ring md5sums
4/4 hosts matched, 0 error[s] while checking hosts.
===============================================================================
[2016-11-16 15:55:26] Checking swift.conf md5sum
4/4 hosts matched, 0 error[s] while checking hosts.
===============================================================================
[2016-11-16 15:55:27] Checking quarantine
[quarantined_objects] low: 0, high: 0, avg: 0.0, total: 0, Failed: 0.0%, no_result: 0, reported: 4
[quarantined_accounts] low: 0, high: 0, avg: 0.0, total: 0, Failed: 0.0%, no_result: 0, reported: 4
[quarantined_containers] low: 0, high: 0, avg: 0.0, total: 0, Failed: 0.0%, no_result: 0, reported: 4
===============================================================================
[2016-11-16 15:55:27] Checking socket usage
[orphan] low: 0, high: 0, avg: 0.0, total: 0, Failed: 0.0%, no_result: 0, reported: 4
[tcp_in_use] low: 14, high: 25, avg: 17.0, total: 68, Failed: 0.0%, no_result: 0, reported: 4
[time_wait] low: 558, high: 896, avg: 750.8, total: 3003, Failed: 0.0%, no_result: 0, reported: 4
[tcp6_in_use] low: 1, high: 1, avg: 1.0, total: 4, Failed: 0.0%, no_result: 0, reported: 4
[tcp_mem_allocated_bytes] low: 28672, high: 380928, avg: 191488.0, total: 765952, Failed: 0.0%, no_result: 0, reported: 4
===============================================================================
[2016-11-16 15:55:28] Validating server type 'object' on 4 hosts...
4/4 hosts ok, 0 error[s] while checking hosts.
===============================================================================
[2016-11-16 15:55:28] Checking drive-audit errors
[drive_audit_errors] - No hosts returned valid data.
===============================================================================
[2016-11-16 15:55:28] Checking time-sync
!! http://10.240.1.60:6000/recon/time current time is 2016-11-16 15:55:28, but remote is 2016-11-16 15:55:28, differs by 0.00 sec
!! http://10.240.1.61:6000/recon/time current time is 2016-11-16 15:55:28, but remote is 2016-11-16 15:55:28, differs by 0.00 sec
!! http://10.240.0.61:6000/recon/time current time is 2016-11-16 15:55:28, but remote is 2016-11-16 15:55:28, differs by 0.00 sec
!! http://10.240.0.60:6000/recon/time current time is 2016-11-16 15:55:28, but remote is 2016-11-16 15:55:28, differs by 0.00 sec
0/4 hosts matched, 0 error[s] while checking hosts.
===============================================================================
```

!!! note

    - **async_pending:** The amount of asyncs or updates to account/container databases, a non-zero value here is normal, if the number is increasing at an alarming rate for the cluster you may have an unmounted account/container drive, a host is down, the cluster is undersized for workload are just a few possible causes.
    - **Replication (Oldest completion,Most recent):** These times should be close to each other if all services are up and no recent downtime on the cluster has occurred (down node, replaced drive). If this is not the case investigate "Oldest completion" node and inspect swift's object log for signs of "swift-object-replicator" entries that occurred recently. If there is a lack of entries restart swift-object-replicator (service swift-object-replicator), you may also wish to restart rsync daemon if /var/log/rsync.log is not being updated after restarting swift-object-replicator.
    - **Getting unmounted drives**: Self explanatory drive is unmounted on server, check/repair/replace.
    - **Checking load:** Check for any high values from mean average, run "swift-recon -lv" for verbose output to identify host with high load. Check node with high load for: Recently unmounted/replaced drive, XFS hang on object file system, hardware defect, read/write cache disabled, BBU drained or dead, bad SAS cable, bad SAS expander, bad JBOD, URE/Pending Sector/Read Errors (check smartctl + dmesg to identify drive) check dmesg for general warnings.
    - **md5 check of swift.conf and rings:** If any nodes fail you may need to inspect configuration and ring files as one or many disagree with each other.

## Unmounted disks:

```shell
# swift-recon -uv
===============================================================================
--> Starting reconnaissance on 4 hosts
===============================================================================
[2016-11-16 15:58:37] Getting unmounted drives from 4 hosts...
-> http://10.240.1.61:6000/recon/unmounted: []
-> http://10.240.1.60:6000/recon/unmounted: [{u'device': u'sdb',u'mounted': False}]
-> http://10.240.0.61:6000/recon/unmounted: []
-> http://10.240.0.60:6000/recon/unmounted: []
Not mounted: sdb on 10.240.1.60:6000
===============================================================================
(swift-13.3.3) root@infra1-swift-proxy-container-342199b9:~# swift-recon -u
===============================================================================
--> Starting reconnaissance on 4 hosts
===============================================================================
[2016-11-16 15:58:47] Getting unmounted drives from 4 hosts...
Not mounted: sdb on 10.240.1.60:6000
===============================================================================
```

!!! note

Login to the problematic host and find the root cause of the issue, some common issues where a drive is reported unmounted:

    - Drive has XFS errors, check syslog and dmesg for XFS related issues. XFS issues are common, further triage will be needed to make sure there is not underlying hardware issues at play.
    - If you find XFS errors in the logs, first try to umount (umount /srv/node/diskXX) the drive and remount (mount -a), this will replay the XFS journal and repair.
    - If the drive fails to mount, you will need to try and perform XFS repair (xfs_repair /dev/sXX), if xfs_repair errors out and cannot repair drive you will be instructed to run xfs_repair with -L flag THIS IS VERY DANGEROUS! YOU ARE AT RISK OF LOOSING DATA. If sufficient replicas exist on the ring you might be better off formatting the drive and have Swift re-create the missing replica on disk.
    - Check S.M.A.R.T data (Self-Monitoring, Analysis and Reporting Technology) Each hard drive has a built on diagnostics and record keeping device. You can query this data to see performance metrics on the misbehaving drive.
      - Two key things to observe
        - Pending Sectors/URE (Unrecoverable Read Error) When a drive attempts to read data from a block and there is underlying issues, usually mechanical or surface defects it will flag the block as a pending sector, meaning it cannot read from that block anymore, whatever data was on that block is corrupt and no longer reliable. The drive will NOT revector that sector until the block is WRITTEN to again. You will continue to have errors until the pending sector is written to. UREs will cause XFS hangs and in some causes system instability. Running badblocks on the device will cause all pending sectors to be vectored.
       - Remapped Sector: There are special reserve space on all drives that user land does not have access to, part of this restricted space are reserve blocks designated by the manufacture in case they shipped the drive with surface/mechanical defects. Once the drive detects a URE and is forced to remap, the URE is "converted" into a remapped sector. Basically the drive will put a pointer from the old bad sector to its reserve space.  Values over 10-20 are cause for concern as there is a high probability that there are mechanical defects.

## Dispersion report:

!!! note

    swift-dispersion-report should be ran on the designated dispersion proxy container in the environment. The purpose of dispersion is to strategically place container and objects along the ring to fulfill the percentage of coverage specified in the /etc/swift/swift-disperson.conf, default is 1%. If you run swift-dispersion-report and it reports no containers exist, your either on the wrong node or swift-dispersion-populate has not been ran. Dispersion is a great tool at determining ring heath and also checks for any permission issues. Permission issues on /srv/node/diskXX wont be flagged with swift-recon since the drive is not unmounted but has issues preventing reads/writes from occurring.   Dispersion is very useful when rebalancing or drive replacement. The data is static so running dispersion after a node reboot or failure/remounting a failed disk will show nothing of value since the dispersion data does not reflect asyncs or missing replicas from disk or current replication lag.

Healthy dispersion report:

```shell
# swift-dispersion-report
Using storage policy: default
Queried 128 containers for dispersion reporting, 1s, 0 retries
100.00% of container copies found (256 of 256)
Sample represents 50.00% of the container partition space
Queried 128 objects for dispersion reporting, 14s, 0 retries
There were 128 partitions missing 0 copies.
100.00% of object copies found (256 of 256)
Sample represents 50.00% of the object partition space
```

Unmounted Drive:

```shell
# swift-dispersion-report
Using storage policy: default
Queried 128 containers for dispersion reporting, 5s, 0 retries
100.00% of container copies found (256 of 256)
Sample represents 50.00% of the container partition space
ERROR: 10.240.1.60:6000/sdb is unmounted -- This will cause replicas designated for that device to be considered missing until resolved or the ring is updated.
Queried 128 objects for dispersion reporting, 20s, 0 retries
There were 93 partitions missing 0 copies.
! There were 35 partitions missing 1 copy.
86.33% of object copies found (221 of 256)
Sample represents 50.00% of the object partition space
```

Dispersion report after failed disk replacement:

```shell
# swift-dispersion-report
Using storage policy: default
Queried 128 containers for dispersion reporting, 2s, 0 retries
100.00% of container copies found (256 of 256)
Sample represents 50.00% of the container partition space
Queried 128 objects for dispersion reporting, 8s, 0 retries
There were 93 partitions missing 0 copies.
! There were 35 partitions missing 1 copy.
86.33% of object copies found (221 of 256)
Sample represents 50.00% of the object partition space
```

Dispersion report after a failed disk replacement minutes later:

```shell
swift-dispersion-report
Using storage policy: default
Queried 128 containers for dispersion reporting, 1s, 0 retries
100.00% of container copies found (256 of 256)
Sample represents 50.00% of the container partition space
Queried 128 objects for dispersion reporting, 2s, 0 retries
There were 120 partitions missing 0 copies.
! There were 8 partitions missing 1 copy.
96.88% of object copies found (248 of 256)
Sample represents 50.00% of the object partition space
```

Dispersion report errors while running:

```shell
# swift-dispersion-report
Using storage policy: default
Queried 128 containers for dispersion reporting, 2s, 0 retries
100.00% of container copies found (256 of 256)
Sample represents 50.00% of the container partition space
ERROR: 10.240.0.61:6000/sdb: 15 seconds
ERROR: 10.240.0.61:6000/sdc: 15 seconds
ERROR: 10.240.0.61:6000/sdc: 15 seconds
ERROR: 10.240.0.61:6000/sdc: 15 seconds
ERROR: 10.240.0.61:6000/sdb: 15 seconds
```

!!! note

    - Out of workers for account/container/object, check load on object server for high usage, you may need to increase worker count, however increasing worker threads might over subscribe node, proceed with caution!
    - Drive is having issues, login to node and check disk that is causing errors.

## Locating Objects in Swift

We will be uploading a file to swift, showing the account/container and object interactions and verifying account/container and object are in their correct place.

!!! info

    Examples provided are with TWO replicas

!!! warning

    Using swift-get-nodes will not verify the AUTH/Container/Object is valid, the use of swift-get-nodes is to provide the hash of the objects location, there is no error checking or validation used in swift-get-nodes!



```shell
# swift upload iso xenial-server-cloudimg-amd64-disk1.img
xenial-server-cloudimg-amd64-disk1.img
# swift stat
                       Account: AUTH_0b4e002d1ab94385ab0895f2aaee33c9
                    Containers: 1
                       Objects: 0
                         Bytes: 0
Containers in policy "default": 1
   Objects in policy "default": 0
     Bytes in policy "default": 0
   X-Account-Project-Domain-Id: default
                 Accept-Ranges: bytes
                   X-Timestamp: 1484158003.79601
                    X-Trans-Id: txe2debd9bced9408393d9d-00587674a7
                  Content-Type: text/plain; charset=utf-8
# swift list
iso
# swift list iso
xenial-server-cloudimg-amd64-disk1.img
```

## Consult the Account ring and verify Account DB placement is correct:

```shell
# swift-get-nodes -a /etc/swift/account.ring.gz AUTH_0b4e002d1ab94385ab0895f2aaee33c9

Account     AUTH_0b4e002d1ab94385ab0895f2aaee33c9
Container    None
Object      None

Partition    108
Hash       6cc6a2e7fbc5af96512b34a75edc682e

Server:Port Device    10.240.1.60:6002 sdd
Server:Port Device    10.240.0.61:6002 sdd
Server:Port Device    10.240.0.60:6002 sdd     [Handoff]
Server:Port Device    10.240.1.61:6002 sdd     [Handoff]

curl -I -XHEAD "http://10.240.1.60:6002/sdd/108/AUTH_0b4e002d1ab94385ab0895f2aaee33c9"
curl -I -XHEAD "http://10.240.0.61:6002/sdd/108/AUTH_0b4e002d1ab94385ab0895f2aaee33c9"
curl -I -XHEAD "http://10.240.0.60:6002/sdd/108/AUTH_0b4e002d1ab94385ab0895f2aaee33c9" #[Handoff]
curl -I -XHEAD "http://10.240.1.61:6002/sdd/108/AUTH_0b4e002d1ab94385ab0895f2aaee33c9" #[Handoff]

Use your own device location of servers: such as "export DEVICE=/srv/node"
ssh 10.240.1.60 "ls -lah ${DEVICE:-/srv/node*}/sdd/accounts/108/82e/6cc6a2e7fbc5af96512b34a75edc682e"
ssh 10.240.0.61 "ls -lah ${DEVICE:-/srv/node*}/sdd/accounts/108/82e/6cc6a2e7fbc5af96512b34a75edc682e"
ssh 10.240.0.60 "ls -lah ${DEVICE:-/srv/node*}/sdd/accounts/108/82e/6cc6a2e7fbc5af96512b34a75edc682e" # [Handoff]
ssh 10.240.1.61 "ls -lah ${DEVICE:-/srv/node*}/sdd/accounts/108/82e/6cc6a2e7fbc5af96512b34a75edc682e" # [Handoff]

note: `/srv/node*` is used as default value of `devices`, the real value is set in the config file on each storage node.
```

Verify placement of the account database, account db should be on primary nodes, handoff nodes indicate a problem or overloaded cluster.

Primary Node:

```shell
# curl -I -XHEAD "http://10.240.1.60:6002/sdd/108/AUTH_0b4e002d1ab94385ab0895f2aaee33c9"
HTTP/1.1 204 No Content
X-Account-Sysmeta-Project-Domain-Id: default
X-Put-Timestamp: 1484158003.80108
X-Account-Object-Count: 1
X-Account-Storage-Policy-Default-Bytes-Used: 322371584
X-Account-Storage-Policy-Default-Object-Count: 1
X-Timestamp: 1484158003.79601
X-Account-Bytes-Used: 322371584
X-Account-Container-Count: 1
Content-Type: text/plain; charset=utf-8
X-Account-Storage-Policy-Default-Container-Count: 1
Content-Length: 0
Date: Wed, 11 Jan 2017 19:16:46 GMT
```

 Primary Node:

```shell
# curl -I -XHEAD "http://10.240.0.61:6002/sdd/108/AUTH_0b4e002d1ab94385ab0895f2aaee33c9"
HTTP/1.1 204 No Content
X-Account-Sysmeta-Project-Domain-Id: default
X-Put-Timestamp: 1484158003.80108
X-Account-Object-Count: 1
X-Account-Storage-Policy-Default-Bytes-Used: 322371584
X-Account-Storage-Policy-Default-Object-Count: 1
X-Timestamp: 1484158003.79601
X-Account-Bytes-Used: 322371584
X-Account-Container-Count: 1
Content-Type: text/plain; charset=utf-8
X-Account-Storage-Policy-Default-Container-Count: 1
Content-Length: 0
Date: Wed, 11 Jan 2017 19:16:46 GMT
```

 Handoff (404 is expected)

```shell
# curl -I -XHEAD "http://10.240.0.60:6002/sdd/108/AUTH_0b4e002d1ab94385ab0895f2aaee33c9" # [Handoff]
HTTP/1.1 404 Not Found
Content-Length: 0
Content-Type: text/html; charset=utf-8
Date: Wed, 11 Jan 2017 19:16:46 GMT
```

  Handoff (404 is expected)

```shell
# curl -I -XHEAD "http://10.240.1.61:6002/sdd/108/AUTH_0b4e002d1ab94385ab0895f2aaee33c9" # [Handoff]
HTTP/1.1 404 Not Found
Content-Length: 0
Content-Type: text/html; charset=utf-8
Date: Wed, 11 Jan 2017 19:16:46 GMT
```

## Consult the Container ring and verify Container DB placement is correct:

```shell
# swift-get-nodes AUTH_0b4e002d1ab94385ab0895f2aaee33c9 iso

Account     AUTH_0b4e002d1ab94385ab0895f2aaee33c9
Container    iso
Object      None

Partition    70
Hash       461a188566b0718ba5fa8ec057b8d78f

Server:Port Device    10.240.1.61:6001 sdd
Server:Port Device    10.240.0.61:6001 sdd
Server:Port Device    10.240.0.60:6001 sdd     [Handoff]
Server:Port Device    10.240.1.60:6001 sdd     [Handoff]

curl -I -XHEAD "http://10.240.1.61:6001/sdd/70/AUTH_0b4e002d1ab94385ab0895f2aaee33c9/iso"
curl -I -XHEAD "http://10.240.0.61:6001/sdd/70/AUTH_0b4e002d1ab94385ab0895f2aaee33c9/iso"
curl -I -XHEAD "http://10.240.0.60:6001/sdd/70/AUTH_0b4e002d1ab94385ab0895f2aaee33c9/iso" #[Handoff]
curl -I -XHEAD "http://10.240.1.60:6001/sdd/70/AUTH_0b4e002d1ab94385ab0895f2aaee33c9/iso" #[Handoff]

Use your own device location of servers: such as "export DEVICE=/srv/node"
ssh 10.240.1.61 "ls -lah ${DEVICE:-/srv/node*}/sdd/containers/70/78f/461a188566b0718ba5fa8ec057b8d78f"
ssh 10.240.0.61 "ls -lah ${DEVICE:-/srv/node*}/sdd/containers/70/78f/461a188566b0718ba5fa8ec057b8d78f"
ssh 10.240.0.60 "ls -lah ${DEVICE:-/srv/node*}/sdd/containers/70/78f/461a188566b0718ba5fa8ec057b8d78f" #[Handoff]
ssh 10.240.1.60 "ls -lah ${DEVICE:-/srv/node*}/sdd/containers/70/78f/461a188566b0718ba5fa8ec057b8d78f" #[Handoff]

note: `/srv/node*` is used as default value of `devices`, the real value is set in the config file on each storage node.
```

 Primary Node:

```shell
# curl -I -XHEAD "http://10.240.1.61:6001/sdd/70/AUTH_0b4e002d1ab94385ab0895f2aaee33c9/iso"
HTTP/1.1 204 No Content
X-Backend-Timestamp: 1484158003.81339
X-Container-Object-Count: 1
X-Put-Timestamp: 1484158024.33580
X-Backend-Put-Timestamp: 1484158024.33580
X-Backend-Delete-Timestamp: 0000000000.00000
X-Container-Bytes-Used: 322371584
X-Timestamp: 1484158003.81339
X-Backend-Storage-Policy-Index: 0
Content-Type: text/plain; charset=utf-8
X-Backend-Status-Changed-At: 1484158003.81664
Content-Length: 0
Date: Wed, 11 Jan 2017 19:17:38 GMT
```

 Primary Node:

```shell
# curl -I -XHEAD "http://10.240.0.61:6001/sdd/70/AUTH_0b4e002d1ab94385ab0895f2aaee33c9/iso"
HTTP/1.1 204 No Content
X-Backend-Timestamp: 1484158003.81339
X-Container-Object-Count: 1
X-Put-Timestamp: 1484158024.33580
X-Backend-Put-Timestamp: 1484158024.33580
X-Backend-Delete-Timestamp: 0000000000.00000
X-Container-Bytes-Used: 322371584
X-Timestamp: 1484158003.81339
X-Backend-Storage-Policy-Index: 0
Content-Type: text/plain; charset=utf-8
X-Backend-Status-Changed-At: 1484158003.81664
Content-Length: 0
Date: Wed, 11 Jan 2017 19:17:38 GMT
```

   Handoff (404 is expected)

```shell
# curl -I -XHEAD "http://10.240.0.60:6001/sdd/70/AUTH_0b4e002d1ab94385ab0895f2aaee33c9/iso" # [Handoff]
HTTP/1.1 404 Not Found
X-Backend-Timestamp: 0000000000.00000
X-Backend-Put-Timestamp: 0000000000.00000
X-Backend-Delete-Timestamp: 0000000000.00000
X-Backend-Storage-Policy-Index: 0
Content-Type: text/html; charset=UTF-8
X-Backend-Status-Changed-At: 0000000000.00000
Content-Length: 0
Date: Wed, 11 Jan 2017 19:17:38 GMT
```

   Handoff (404 is expected)

```shell
# curl -I -XHEAD "http://10.240.1.60:6001/sdd/70/AUTH_0b4e002d1ab94385ab0895f2aaee33c9/iso" # [Handoff]
HTTP/1.1 404 Not Found
X-Backend-Timestamp: 0000000000.00000
X-Backend-Put-Timestamp: 0000000000.00000
X-Backend-Delete-Timestamp: 0000000000.00000
X-Backend-Storage-Policy-Index: 0
Content-Type: text/html; charset=UTF-8
X-Backend-Status-Changed-At: 0000000000.00000
Content-Length: 0
Date: Wed, 11 Jan 2017 19:17:39 GMT
```

##  Consult Object ring and verify placement of Objects

```shell
# swift-get-nodes -a /etc/swift/object.ring.gz AUTH_0b4e002d1ab94385ab0895f2aaee33c9 iso xenial-server-cloudimg-amd64-disk1.img

Account     AUTH_0b4e002d1ab94385ab0895f2aaee33c9
Container    iso
Object      xenial-server-cloudimg-amd64-disk1.img

Partition    182
Hash       b6716383aa4a99bf3eb68c46453652d4

Server:Port Device    10.240.1.60:6002 sdd
Server:Port Device    10.240.0.61:6002 sdd
Server:Port Device    10.240.1.61:6002 sdd     [Handoff]
Server:Port Device    10.240.0.60:6002 sdd     [Handoff]

curl -I -XHEAD "http://10.240.1.60:6002/sdd/182/AUTH_0b4e002d1ab94385ab0895f2aaee33c9/iso/xenial-server-cloudimg-amd64-disk1.img"
curl -I -XHEAD "http://10.240.0.61:6002/sdd/182/AUTH_0b4e002d1ab94385ab0895f2aaee33c9/iso/xenial-server-cloudimg-amd64-disk1.img"
curl -I -XHEAD "http://10.240.1.61:6002/sdd/182/AUTH_0b4e002d1ab94385ab0895f2aaee33c9/iso/xenial-server-cloudimg-amd64-disk1.img" #[Handoff]
curl -I -XHEAD "http://10.240.0.60:6002/sdd/182/AUTH_0b4e002d1ab94385ab0895f2aaee33c9/iso/xenial-server-cloudimg-amd64-disk1.img" #[Handoff]

Use your own device location of servers: such as "export DEVICE=/srv/node"
ssh 10.240.1.60 "ls -lah ${DEVICE:-/srv/node*}/sdd/objects/182/2d4/b6716383aa4a99bf3eb68c46453652d4"
ssh 10.240.0.61 "ls -lah ${DEVICE:-/srv/node*}/sdd/objects/182/2d4/b6716383aa4a99bf3eb68c46453652d4"
ssh 10.240.1.61 "ls -lah ${DEVICE:-/srv/node*}/sdd/objects/182/2d4/b6716383aa4a99bf3eb68c46453652d4" #[Handoff]
ssh 10.240.0.60 "ls -lah ${DEVICE:-/srv/node*}/sdd/objects/182/2d4/b6716383aa4a99bf3eb68c46453652d4" #[Handoff]

note: `/srv/node*` is used as default value of `devices`, the real value is set in the config file on each storage node.
```

Use curl commands above to verify the object is correctly placed on the primary devices.

## Inspect Swift Object on storage disk:

```shell
# swift-object-info sdb/objects/182/2d4/b6716383aa4a99bf3eb68c46453652d4/1484158024.61997.data
Path: /AUTH_0b4e002d1ab94385ab0895f2aaee33c9/iso/xenial-server-cloudimg-amd64-disk1.img
 ``Account: AUTH_0b4e002d1ab94385ab0895f2aaee33c9
 ``Container: iso
 ``Object: xenial-server-cloudimg-amd64-disk1.img
 ``Object hash: b6716383aa4a99bf3eb68c46453652d4
Content-Type: application/octet-stream
Timestamp: 2017-01-11T18:07:04.619970 (1484158024.61997)
System Metadata:
 ``No metadata found
User Metadata:
 ``X-Object-Meta-Mtime: 1483724080.000000
Other Metadata:
 ``No metadata found
ETag: 0924ed40babf9fa5bbfb51844c7adfbc (valid)
Content-Length: 322371584 (valid)
Partition    182
Hash       b6716383aa4a99bf3eb68c46453652d4
Server:Port Device    10.240.0.61:6000 sdb
Server:Port Device    10.240.1.61:6000 sdb
Server:Port Device    10.240.1.60:6000 sdb     [Handoff]
Server:Port Device    10.240.0.60:6000 sdc     [Handoff]

curl -I -XHEAD "http://10.240.0.61:6000/sdb/182/AUTH_0b4e002d1ab94385ab0895f2aaee33c9/iso/xenial-server-cloudimg-amd64-disk1.img" -H "X-Backend-Storage-Policy-Index: 0"
curl -I -XHEAD "http://10.240.1.61:6000/sdb/182/AUTH_0b4e002d1ab94385ab0895f2aaee33c9/iso/xenial-server-cloudimg-amd64-disk1.img" -H "X-Backend-Storage-Policy-Index: 0"
curl -I -XHEAD "http://10.240.1.60:6000/sdb/182/AUTH_0b4e002d1ab94385ab0895f2aaee33c9/iso/xenial-server-cloudimg-amd64-disk1.img" -H "X-Backend-Storage-Policy-Index: 0" # [Handoff]
curl -I -XHEAD "http://10.240.0.60:6000/sdc/182/AUTH_0b4e002d1ab94385ab0895f2aaee33c9/iso/xenial-server-cloudimg-amd64-disk1.img" -H "X-Backend-Storage-Policy-Index: 0" # [Handoff]

Use your own device location of servers: such as "export DEVICE=/srv/node"
ssh 10.240.0.61 "ls -lah ${DEVICE:-/srv/node*}/sdb/objects/182/2d4/b6716383aa4a99bf3eb68c46453652d4"
ssh 10.240.1.61 "ls -lah ${DEVICE:-/srv/node*}/sdb/objects/182/2d4/b6716383aa4a99bf3eb68c46453652d4"
ssh 10.240.1.60 "ls -lah ${DEVICE:-/srv/node*}/sdb/objects/182/2d4/b6716383aa4a99bf3eb68c46453652d4" # [Handoff]
ssh 10.240.0.60 "ls -lah ${DEVICE:-/srv/node*}/sdc/objects/182/2d4/b6716383aa4a99bf3eb68c46453652d4" # [Handoff]

note: `/srv/node*` is used as default value of `devices`, the real value is set in the config file on each storage node.
```

##  Read XFS metadata of object on disk:

Create swift-meta.py file:

```bash
# swift-meta.py
import pickle
with open("/dev/stdin") as f:
  ``print pickle.loads(f.read())
```

Read file's metadata from object node:

```bash
# getfattr -d --only-values -n user.swift.metadata /mnt/sdb/objects/182/2d4/b6716383aa4a99bf3eb68c46453652d4/1484158024.61997.data | python swift-meta.py
getfattr: Removing leading '/' from absolute path names
{'Content-Length': '322371584', 'name': '/AUTH_0b4e002d1ab94385ab0895f2aaee33c9/iso/xenial-server-cloudimg-amd64-disk1.img', 'Content-Type': 'application/octet-stream', 'ETag': '0924ed40babf9fa5bbfb51844c7adfbc', 'X-Timestamp': '1484158024.61997', 'X-Object-Meta-Mtime': '1483724080.000000’}
```

[More information can be found here](https://docs.openstack.org/swift/latest/)
