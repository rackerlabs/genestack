# OpenStack Ironic Python Agent Log Redactor

Genestack can run an `ipa-log-redactor` sidecar in each Ironic conductor Pod.
During deployment and cleaning, the Ironic Python Agent (IPA) sends a
compressed diagnostic bundle to the conductor, which stores it in
`/var/lib/ironic/logs`. The sidecar reads those bundles, redacts known secrets,
and writes the result to standard output. The OpenTelemetry (OTel) DaemonSet
collector reads that output from `/var/log/pods` and forwards it to Loki, where
operators search it in Grafana.

This guide describes how the redactor works, how to enable it, and how to
validate it. For Ironic deployment and bare metal provisioning, see
[Deploy Ironic](openstack-ironic.md) and the
[OpenStack Ironic Operational Guide](openstack-ironic-operational-guide.md).

!!! note
    The sidecar is optional and is not part of the default Ironic deployment.
    It is supplied as an example override that you copy into place.

## Why use it

Without the redactor, IPA bundles stay on the conductor host. Operators cannot
search them centrally, and a bundle may go unnoticed until someone inspects the
conductor. Forwarding the raw files is not safe either, because they can
contain agent tokens, root passwords, BMC credentials, configdrive data, and
credentials embedded in URLs.

The redactor addresses this by:

- Waiting until a bundle has stopped changing before it reads it.
- Forwarding only the `journal`, `ip_addr`, `lsblk`, and `dmesg` members.
- Redacting known secret formats line by line before anything is written.
- Marking every bundle as forwarded or failed, with bounded retention.
- Applying size and line limits so a damaged or hostile archive cannot
  exhaust memory or flood the logging pipeline.

## Architecture

```text
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                                 Ironic Conductor Pod                                │
│                                                                                     │
│ ┌──────────────────┐   ┌──────────────────────┐   ┌───────────────────────────────┐ │
│ │ ironic-conductor │──►│ /var/lib/ironic/logs │◄──│        ipa-log-redactor       │ │
│ └──────────────────┘   │ (hostPath, subPath)  │   │           (sidecar)           │ │
│                        └──────────────────────┘   │                               │ │
│                                                   │ 1. wait until stable          │ │
│                                                   │ 2. claim .processing          │ │
│                                                   │ 3. extract members            │ │
│                                                   │ 4. redact and print to stdout │ │
│                                                   │ 5. rename .forwarded/.failed  │ │
│                                                   └───────────────────────────────┘ │
│                                                                   │                 │
└───────────────────────────────────────────────────────────────────┬─────────────────┘
                                                                    │ stdout
                                           ┌────────────────────────┘
                                           ▼
                    ┌─────────────────────────────────────────────┐
                    │    Node /var/log/pods (CRI container log)   │
                    └─────────────────────────────────────────────┘
                                           │
                                           ▼
                    ┌─────────────────────────────────────────────┐
                    │  OpenTelemetry DaemonSet (filelog receiver) │
                    └─────────────────────────────────────────────┘
                                           │
                                           ▼
                    ┌─────────────────────────────────────────────┐
                    │              Loki  ──►  Grafana             │
                    └─────────────────────────────────────────────┘
```

The sidecar exposes no port and does not talk to OTel or Loki directly. The
container runtime writes its standard output below `/var/log/pods`, and the
existing OTel `filelog` receiver collects it like any other container log.

## Prerequisites

Before enabling the sidecar, ensure that:

- Ironic is deployed and its conductors are healthy.
- The logging stack (OpenTelemetry, Loki, and Grafana) is installed. See
  [Monitoring Getting Started](monitoring-getting-started.md) and
  [Genestack Logging](genestack-logging.md).
- Ironic is configured to store IPA logs locally.
- The `ipa-log-redactor` image is available to the cluster.

### Ironic must store IPA logs locally

Ironic can retrieve the logs from the deploy ramdisk (the IPA) and package them
as a `.tar.gz` bundle. Three options in the `[agent]` section of `ironic.conf`
decide whether and where the bundle is stored. See the upstream
[Retrieving logs from the deploy ramdisk](https://docs.openstack.org/ironic/latest/admin/troubleshooting.html#retrieving-logs-from-the-deploy-ramdisk)
section for the full description.

| Option | Values | Upstream default | Genestack |
| --- | --- | --- | --- |
| `deploy_logs_collect` | `on_failure`, `always`, `never` | `on_failure` | `always` |
| `deploy_logs_storage_backend` | `local`, `swift` | `local` | `local` |
| `deploy_logs_local_path` | A directory on the conductor | `/var/log/ironic/deploy` | `/var/lib/ironic/logs` |

With the `local` backend, Ironic writes each bundle to `deploy_logs_local_path`
on the conductor's own file system, and the sidecar reads it from there. With
the `swift` backend, Ironic uploads the bundle to a Swift container
(`deploy_logs_swift_container`, expiring after
`deploy_logs_swift_days_to_expire` days) and writes nothing to the conductor, so
the sidecar has nothing to process. The sidecar supports only the `local`
backend.

`deploy_logs_collect` controls which deployments produce a bundle. The upstream
default, `on_failure`, retrieves logs only when a deployment fails. Genestack
sets `always`, so successful deployments produce a bundle as well.

Upstream advises operators to consider rotating bundles stored on the local
file system to avoid disk space problems. The redactor's retention setting
deletes bundles a set time after they have been forwarded or have failed. See
[Retention and dry run](#retention-and-dry-run).

The base Genestack Ironic overrides already select the `local` backend and
store the bundles in the directory the sidecar watches:

```yaml
conf:
  ironic:
    agent:
      deploy_logs_collect: "always"
      deploy_logs_storage_backend: "local"
      deploy_logs_local_path: "/var/lib/ironic/logs"
```

If you changed `deploy_logs_local_path`, set `LOGS_DIR` and the volume mount in
the sidecar override to the same location. If you switch
`deploy_logs_storage_backend` to `swift`, the sidecar stops receiving new
bundles.

### Host directory

The sidecar mounts only the `logs` subdirectory of the conductor's
`host-var-lib-ironic` volume, so it cannot see Ironic certificates, images, or
other conductor data.

You do not need to create this directory. It is created automatically when it
is missing:

- Ironic creates `deploy_logs_local_path` when it stores a bundle and the
  directory does not exist, so setting that path is enough.
- When the sidecar is added, the kubelet also creates a missing `subPath`
  directory while it sets up the Pod's volume mounts, before the containers
  start.

## Enable the sidecar

Genestack ships the sidecar as an example override. The Ironic install script
loads only files ending in `.yaml`, so the `.example` file has no effect until
you copy it:

```shell
cp \
  /opt/genestack/base-helm-configs/ironic/ipa-log-redactor-helm-overrides.yaml.example \
  /etc/genestack/helm-configs/ironic/ipa-log-redactor-helm-overrides.yaml
```

The override adds the container through `conductor.extraContainers`:

```yaml
--8<-- "base-helm-configs/ironic/ipa-log-redactor-helm-overrides.yaml.example"
```

The example uses the `latest` tag, which the image build publishes along with a
timestamped tag. The example also sets `imagePullPolicy: IfNotPresent`, so a
node that already pulled `latest` keeps using that copy after the image is
rebuilt. For production, pin the timestamped tag or an image digest from build,
or set `imagePullPolicy: Always`. Then upgrade Ironic:

```shell
/opt/genestack/bin/install-ironic.sh
```

Files in `/etc/genestack/helm-configs/ironic/` take precedence over the base
overrides, so environment-specific changes belong there.

### Security context

The example override sets a `securityContext` on the sidecar. The Ironic chart
runs the conductor Pod as root, and the conductor creates the bundles as
`root:root`, so the sidecar runs as root to act as their owner. That is enough
to rename, relink, and delete them, so the rest of the container is locked down.
It cannot gain privileges, has no Linux capabilities, uses the runtime default
seccomp profile, and has a read-only root filesystem. Only the mounted logs
directory is writable.

!!! note
    The image defines a non-root `ironic` user (UID/GID `42424`) and runs as it
    when started on its own. That user can process bundles only if the shared
    directory is owned by, or writable for, UID/GID `42424`. In a conductor Pod
    that runs as root, keep the `securityContext` from the example.

## Bundle format and allow-list

The redactor processes bundles named:

```text
{node_uuid}_{node_name}_{instance_uuid-or-cleaning}_{timestamp}.tar.gz
```

For example:

```text
15b5e16a-78dd-4d25-b902-6ae43d4c3d2c_node1_280abae5-79c7-47e1-ac26-c22a831077bb_2026-09-09-07-04-12.tar.gz
a5c9b689-28db-4f8b-ad4b-99d0902caf3e_node2_cleaning_2026-09-14-04-12-03.tar.gz
```

Both deployment bundles (with an instance UUID) and cleaning bundles are
processed. Only these archive members are forwarded:

| Member | Requirement | Purpose |
| --- | --- | --- |
| `journal` | Required | IPA and system journal output |
| `ip_addr` | Optional | Network interface and address information |
| `lsblk` | Optional | Block device information |
| `dmesg` | Optional | Kernel messages |

Other members are never forwarded, but their declared sizes still count toward
the total uncompressed size limit.

## What is redacted

The redactor replaces the values of these keys, case-insensitively, in
`key=value`, `key: value`, and dictionary (`'key': 'value'`) forms:

```text
ipa-agent-token, agent_token, agent_secret_token,
agent_secret_token_pregenerated, redfish_username, redfish_password,
image_server_password, configdrive, root_password, rootpwd, sshkey,
kernel_append_params, ssh_authorized_keys
```

It also redacts:

- `Authorization`, `X-Auth-Token`, `X-Subject-Token`, and `X-Service-Token`
  values.
- User and password credentials embedded in `http`, `https`, `ftp`, `ftps`,
  and `sftp` URLs.
- Secret query parameters in signed image URLs, such as `temp_url_sig`,
  `X-Amz-Signature`, `X-Amz-Credential`, `X-Amz-Security-Token`,
  `AWSAccessKeyId`, `Signature`, `token`, and `sig`. The parameter names and
  non-secret parameters stay visible.
- Multiline private key blocks, including PGP private key blocks.
- Bare OpenSSH public keys.

Key names are matched exactly. A key that only starts with a secret name, such
as `agent_token_required`, is not redacted, because it is a setting and not a
secret.

!!! warning
    Redaction works from a known list. A generic `password=` or `token=`
    outside a URL query string, and a URL password that contains a raw `/`, are
    not redacted. IPA logs can also contain internal IP addresses, MAC
    addresses, hostnames, hardware details, and identifiers. Restrict access to
    Loki and Grafana accordingly, and report new secret formats so the redactor
    can be extended.

## Configuration

The sidecar is configured with environment variables. `LOGS_DIR` is required.

| Variable | Default | Meaning |
| --- | ---: | --- |
| `LOGS_DIR` | Required | Directory containing IPA bundles |
| `INTERVAL` | `30` s | Delay between scans |
| `STABILITY_SECONDS` | `60` s | Time a bundle's size and modification time must stay unchanged before it is read |
| `STATUS_INTERVAL_SECONDS` | `300` s | Delay between heartbeat records; `0` disables them |
| `FORWARDED_RETENTION_DAYS` | `90` | Days to keep `.forwarded` bundles; `0` disables deletion |
| `FAILED_RETENTION_DAYS` | `90` | Days to keep `.failed` bundles; `0` disables deletion |
| `CLEANUP_INTERVAL_SECONDS` | `3600` s | Delay between retention scans |
| `RETENTION_DRY_RUN` | see below | Report cleanup without deleting files |
| `MAX_ARCHIVE_BYTES` | 32 MiB | Maximum compressed bundle size |
| `MAX_TOTAL_ARCHIVE_BYTES` | 512 MiB | Maximum declared size of all members |
| `MAX_MEMBER_BYTES` | 64 MiB | Maximum size of a forwarded member |
| `MAX_LINE_BYTES` | 1 MiB | Maximum size of one line |
| `MAX_OUTPUT_LINES` | `100000` | Maximum records written for one bundle |
| `MAX_PROCESSING_ATTEMPTS` | `3` | Attempts for a bundle that cannot be marked before retries stop |
| `RETRY_BACKOFF_SECONDS` | `60` s | Delay before the first retry; doubles per attempt, capped at one hour |

The size and line limits also have `MAX_TOTAL_OUTPUT_BYTES`,
`MAX_FORWARDED_BYTES`, and `MAX_ARCHIVE_MEMBERS` counterparts. Their defaults
are suitable for normal bundles and rarely need changing.

### Retention and dry run

The redactor keeps the bundle after processing and only changes its suffix, so
the original compressed data stays on the conductor host:

```text
*.tar.gz  ──►  *.tar.gz.processing  ──┬──►  *.tar.gz.forwarded
                                      └──►  *.tar.gz.failed
```

Outcome files are deleted after their retention period, which starts when the
bundle reaches its outcome and not when Ironic created it.

!!! warning
    `RETENTION_DRY_RUN` is `true` in the Python code but `false` in the
    container image. The example override sets it to `"true"` explicitly, so
    the first rollout reports what it would delete and removes nothing. After
    you confirm the cleanup records and timestamps, set it to `"false"` in your
    override and upgrade Ironic to enable deletion.

## Log output

The sidecar writes two kinds of records to standard output. Lifecycle records
are JSON. Content records carry the node name, a short archive ID, and the
member name.

```text
[ipa-log-redactor] {"event":"redactor_started","status":"watching","logs_dir":"/var/lib/ironic/logs","pending_archives":1,"processing_archives":0,"forwarded_archives":0,"failed_archives":0}
[ipa-log-redactor] {"event":"archive_start","archive_id":"8f41c912db90d947","attempt_id":"7a9a1436-ae44-4bc6-a743-a459201cba23","status":"processing","archive_name":"15b5e16a-78dd-4d25-b902-6ae43d4c3d2c_node1_280abae5-79c7-47e1-ac26-c22a831077bb_2026-09-09-07-04-12.tar.gz"}
[ipa-log-redactor] [archive_id=8f41c912db90d947] ===================== journal =====================
[node1] [archive=8f41c912db90d947] [journal] IPA service started
[node1] [archive=8f41c912db90d947] [journal] agent_token=REDACTED
[ipa-log-redactor] {"event":"archive_complete","archive_id":"8f41c912db90d947","attempt_id":"7a9a1436-ae44-4bc6-a743-a459201cba23","status":"processed"}
```

| Event | Meaning |
| --- | --- |
| `redactor_started` | The sidecar started, with its watched directory and an inventory of bundles by state. |
| `redactor_status` | Heartbeat, written every `STATUS_INTERVAL_SECONDS`. |
| `archive_start` | Processing began. Contains the full bundle name. |
| `archive_complete` | All selected content was written and the bundle was marked `.forwarded`. |
| `archive_failed` | Processing failed. Contains a controlled `error_code`, never raw error text. |
| `archive_retry_limit_reached` | A bundle could not be marked after `MAX_PROCESSING_ATTEMPTS` attempts. Written to stderr. |

The full bundle name appears once, in `archive_start`, so it is not repeated on
every content line. To find all lines for one bundle, search for its
`archive_id`.

- `archive_id` is a 16-character hash of the original file name. It stays the
  same if the same bundle is retried.
- `attempt_id` is a random UUID for one processing attempt. A retry keeps the
  `archive_id` and gets a new `attempt_id`.

!!! warning
    Delivery is at least once. If the sidecar stops after some lines reach
    standard output but before the bundle is marked, the bundle is processed
    again. Queries and alerts should tolerate repeated archive IDs.
    `archive_complete` shows that the content was written to standard output
    and the local bundle was marked `.forwarded`. It does not prove that Loki
    stored the records.

## Collection by OpenTelemetry

The Genestack OTel DaemonSet collector reads every container log under
`/var/log/pods/*/*/*.log`, so the sidecar's output is collected with no extra
collector configuration. See [Genestack Logging](genestack-logging.md) for the
receiver configuration. If you restricted the receiver's include or exclude
lists, make sure the `openstack` namespace and the `ipa-log-redactor` container
are allowed.

In Loki, the records carry these labels, among others:

| Label | Value |
| --- | --- |
| `namespace` | `openstack` |
| `statefulset` | `ironic-conductor` |
| `pod` / `k8s_pod_name` | `ironic-conductor-0`, `ironic-conductor-1`, and so on |
| `container` / `service_name` | `ipa-log-redactor` |
| `node` | The Kubernetes node running the conductor |

The timestamp that Grafana shows is the Loki entry time, which comes from the
container runtime's log record. A journal line also contains its original
event time, and a `dmesg` line has a kernel-relative time. These are different
clocks and can appear together.

## Validate

### Check the sidecar

Confirm that every conductor Pod includes the container and that it is running:

```shell
kubectl --namespace openstack get pods \
  -l application=ironic,component=conductor
kubectl --namespace openstack get pods \
  -l application=ironic,component=conductor \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].name}{"\n"}{end}'
```

Read the sidecar log in one conductor Pod:

```shell
CONDUCTOR_POD=$(kubectl --namespace openstack get pods \
  -l application=ironic,component=conductor \
  -o jsonpath='{.items[0].metadata.name}')
kubectl --namespace openstack logs "${CONDUCTOR_POD}" \
  --container ipa-log-redactor
```

A healthy idle sidecar shows `redactor_started` and then a `redactor_status`
record every five minutes. The counters report how many bundles are pending,
processing, forwarded, and failed.

### Check the bundles

List the bundles and their states:

```shell
kubectl --namespace openstack exec "${CONDUCTOR_POD}" \
  --container ipa-log-redactor -- \
  ls -l /var/lib/ironic/logs
```

A bundle that has been handled ends in `.forwarded` or `.failed`. A new bundle
stays `.tar.gz` until it has been stable for `STABILITY_SECONDS`.

### Check Grafana

In Grafana Explore, select the Loki data source and run:

```logql
{statefulset="ironic-conductor", container="ipa-log-redactor"}
```

After a deployment or cleaning, you should see an `archive_start`, one section
header per member, the content lines, and an `archive_complete`.

Confirm that known secrets do not appear. Search for a secret key and check
that every value shows `REDACTED`:

```logql
{statefulset="ironic-conductor", container="ipa-log-redactor"} |~ "(?i)(agent_token|rootpwd|redfish_password|configdrive)"
```

Lines that show `agent_token_required` with a value of `True` are expected. That
is an Ironic setting and not a secret, so the redactor leaves it visible.

## Useful Grafana queries

All redactor output from one conductor Pod:

```logql
{statefulset="ironic-conductor", container="ipa-log-redactor", k8s_pod_name="ironic-conductor-0"}
```

Bundle lifecycle records across all conductors:

```logql
{statefulset="ironic-conductor", container="ipa-log-redactor"}
|~ `"event":"archive_(start|complete|failed)"`
```

Failed bundles:

```logql
{statefulset="ironic-conductor", container="ipa-log-redactor"}
|= `"event":"archive_failed"`
```

Journal content only:

```logql
{statefulset="ironic-conductor", container="ipa-log-redactor"}
|= "[journal]"
```

One bundle, using the `archive_id` from its `archive_start` record:

```logql
{statefulset="ironic-conductor", container="ipa-log-redactor"}
|= "8f41c912db90d947"
```

Detect a silent sidecar. This returns a series for each conductor that has sent
a heartbeat in the last 15 minutes. A conductor missing from the result has not:

```logql
sum by (k8s_pod_name) (
  count_over_time({statefulset="ironic-conductor", container="ipa-log-redactor"}
    |= `"event":"redactor_status"` [15m])
)
```

## Limitations

- Redaction is limited to the known formats listed above and is a
  risk-reduction control, not a replacement for access control.
- Delivery to Loki is at least once, and the sidecar cannot confirm that Loki
  stored a record.
- Only the `journal`, `ip_addr`, `lsblk`, and `dmesg` members are forwarded.
- Only the Ironic `local` log storage backend is supported. Bundles that Ironic
  uploads to Swift are not read.
- The sidecar tracks retry attempts in memory, so a container restart gives a
  stuck bundle a fresh set of attempts.
- The sidecar watches one directory per conductor Pod. Each conductor processes
  only the bundles stored on its own host.
