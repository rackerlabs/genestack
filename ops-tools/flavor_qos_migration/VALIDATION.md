# Flavor QoS lifecycle validation

This procedure validates that Neutron flavor QoS policies, assigned through
the `flavor_qos:policy_id` flavor extra spec by the cutover tool, survive the
Nova instance lifecycle: resize with confirm, resize with revert, cold
migration, and live migration.

!!! warning

    Run this procedure only against DFW.dev. Never run it against production.
    It mutates instance, port, and QoS state.

## Connection model

The procedure uses two credential scopes deliberately.

Tenant-scope operations — listing servers and floating IPs from the test
project, security-group membership, and floating-IP association — run from
the local workstation with the member-scoped test cloud:

```bash
source <workstation-venv>/bin/activate
openstack --os-cloud dfw-dev-me ...
```

Administrative operations — Neutron QoS policy reads, cross-project Nova and
Neutron observation, and Kubernetes access — run from the DFW.dev overseer
with the admin cloud:

```bash
flex-dfw-dev
source /home/ubuntu/.venvs/genestack/bin/activate
openstack --os-cloud default ...
kubectl -n openstack ...
```

Use the `flex-dfw-dev` alias for the overseer session instead of embedding
gateway details into test scripts.

Constraints:

- Neutron QoS policy operations require admin credentials. The `default`
  cloud on the overseer is the only scope used for QoS and cross-project
  reads.
- Use only DFW.dev resources. Every server, port, policy, floating IP, and
  security group must belong to the DFW.dev deployment.
- SSH and data-plane access to a test VM requires one floating IP from the
  predefined DFW.dev floating IP pool plus the `ssh-in`, `ping-in`, and
  `iperf3` security groups. All floating IPs and security groups must come
  from the `dfw-dev-me` project.

## Derive every identifier at run time

Never copy identifiers from a previous run. Server UUIDs, port UUIDs, policy
UUIDs, and floating IPs change between fixture rebuilds, and instance names
are not unique — the test pool has previously held two servers with the same
name on different flavors. Resolve everything read-only at the start of each
run and record the values in the run log.

### Server UUIDs

List the pool and pin servers by UUID, never by name:

```bash
openstack --os-cloud dfw-dev-me server list \
  -c ID -c Name -c Status -c Flavor -f table
```

Record for each chosen fixture: UUID, name, status, flavor. Where a name
appears more than once, the flavor column disambiguates; key all later
commands off the UUID only.

### Compute-owned ports

```bash
SERVER=<server-uuid>

openstack --os-cloud default port list \
  --server "$SERVER" \
  -c ID -c Name -c Status -c "Binding Host ID" -c "QoS Policy ID"
```

Record the compute-owned port UUID(s) for the server. Multi-NIC servers must
have every compute-owned port checked in each predicate below.

### Expected policy per flavor

The expected policy for an instance is whatever its **current** flavor
declares, resolved at run time from the flavor extra spec:

```bash
openstack --os-cloud default flavor show <flavor-name> \
  -c name -c extra_specs -f yaml
```

`extra_specs.flavor_qos:policy_id` is the expected policy UUID for every
compute-owned port of an instance on that flavor. A flavor without this extra
spec has not been migrated and is not a valid test subject or target.

### Policy UUIDs by name

The four regional policies (`lite`, `plus`, `pro`, `elite`) are looked up by
name in the owning project at run time:

```bash
openstack --os-cloud default network qos policy list \
  -c ID -c Name -c Project -c Shared -f table
```

Map each policy UUID back to its name for the run log. The flavor-to-policy
mapping of record is `flavor_qos_mapping.yaml` in this directory; treat live
API output as authoritative for UUIDs and this file as authoritative for
which policy class a flavor should have.

### Baseline gate

Before every lifecycle operation, record the server and port state and apply
the gate:

```bash
openstack --os-cloud default server show "$SERVER" \
  -c status \
  -c OS-EXT-STS:task_state \
  -c OS-EXT-STS:vm_state \
  -c OS-EXT-SRV-ATTR:host \
  -c flavor \
  -f yaml

openstack --os-cloud default port show "$PORT" \
  -c binding_host_id \
  -c binding_profile \
  -c qos_policy_id \
  -f yaml
```

Gate, aligned with the migration tool's preflight:

- **Pass:** `OS-EXT-STS:vm_state` is `active`, `OS-EXT-STS:task_state` is
  empty, port `binding_host_id` equals the server host, and port
  `qos_policy_id` equals the policy UUID from the cached flavor's flavor
  extra spec.
- **Hard stop:** `vm_state` is `resized` (instance awaiting resize confirm or
  revert) or `task_state` is non-null. Do not start a lifecycle test, and do
  not run the migration tool, until the state clears. These are the same
  conditions the tool refuses on.
- **Warning, not a blocker:** a non-terminal row in Nova's `migrations` table
  for an instance whose `vm_state` is stable and whose `task_state` is empty
  is stale historical data. The migration tool reports it as a warning and
  proceeds; this procedure does the same, but the operator must record the
  stale migration identifiers in the run log before continuing.

## Resize target selection

An in-flight policy bug is invisible if source and target map to the same
policy, so every resize in this procedure must cross a policy boundary.

For the standard DFW.dev pool on `gp.8.2.4`:

- Source: `gp.8.2.4` maps to `lite`.
- Valid targets: `gp.8.4.8` or `gp.8.8.16` (`plus`), or `gp.8.16.32`
  (`elite`).
- Source and target must map to different policy classes in
  `flavor_qos_mapping.yaml`. If a future pool uses a different source
  flavor, pick the target from a different policy class using that file.

Do not resize into `gp.8.1.2` or another `lite` flavor: same policy class,
no observable change, useless test.

Pre-resize gate, before every resize in any test:

```bash
openstack --os-cloud default flavor show <target-flavor> \
  -c name -c extra_specs -f yaml
```

- **Pass:** the target flavor carries a non-null `flavor_qos:policy_id`, and
  its value differs from the source flavor's value.
- **Configuration error, not a test failure:** the target flavor has no
  `flavor_qos:policy_id`. Resizing into an unmigrated flavor leaves the port
  with no policy and would read as a false test failure. Stop, run the
  migration tool dry-run for the missing flavor, and fix the configuration
  before executing any test against it.

Record from the gate: source policy UUID and name, target policy UUID and
name. Both must be known before the resize starts, so every predicate below
is an exact comparison rather than a judgment of "looks right".

## Common predicates

Each test applies these named predicates at its listed observation points.
`P1`/`P2` use the values captured in the gates above.

- **P1 — policy equals expectation:** `qos_policy_id` of every
  compute-owned port equals a named recorded policy UUID. Pass is exact
  string equality; missing, null, or any other UUID fails.
- **P2 — binding follows the instance:** port `binding_host_id` equals the
  server's `OS-EXT-SRV-ATTR:host`. Pass is exact string equality.
- **P3 — instance settled:** `status` is `ACTIVE` and `task_state` is
  empty.
- **P4 — flavor current:** the `flavor` field of `server show` equals the
  expected flavor name at that point in the test.

## Test 1: resize and confirm

Purpose: changing flavor must apply the target flavor's policy and it must
survive confirmation.

1. Baseline gate on the chosen fixture. P1 with the source policy, P2, P3,
   P4 with the source flavor.
2. Pre-resize gate. Record source and target policy UUIDs.
3. Resize:

   ```bash
   openstack --os-cloud default server resize \
     --flavor <target-flavor> \
     --wait "$SERVER"
   ```

4. During `VERIFY_RESIZE`, capture the request id from the event list for
   log correlation, then assert: P1 with the **target** policy, P2, P4 with
   the target flavor.
5. Confirm:

   ```bash
   openstack --os-cloud default server resize confirm "$SERVER"
   ```

6. After confirmation assert: P3, P4 with the target flavor, P1 with the
   target policy (the policy must persist after confirm), P2.

## Test 2: resize and revert

Purpose: the target policy must appear during resize and the original policy
must be fully restored on revert.

1. Baseline gate and pre-resize gate as in Test 1.
2. Resize as in Test 1 and assert P1 with the target policy during
   `VERIFY_RESIZE`. Record the request id.
3. Revert:

   ```bash
   openstack --os-cloud default server resize revert "$SERVER"
   ```

4. After revert assert: P3, P4 with the **original** flavor, P1 with the
   **original** policy, P2.
5. Inspect the Nova cell `instance_extra` cached flavor for the instance
   (through the same MariaDB access the migration tool uses) and assert the
   serialized current flavor carries the original policy in
   `nova_object.data.extra_specs` and that no stale resize `old`/`new`
   object is driving port policy. This is the exact field the migration tool
   rewrites, so a stale value here predicts a wrong policy on the next port
   event.
6. Repeat the cycle once (A→B→A) and re-assert step 4. The repeat must not
   reuse a stale migration identifier or stale cached flavor.

## Test 3: cold migration

Purpose: a host-only migration must preserve the current flavor's policy
exactly, with no re-derivation.

1. Baseline gate. Record source host, flavor, policy UUID, and port binding.
2. Migrate:

   ```bash
   openstack --os-cloud default server migrate --wait "$SERVER"
   ```

   If Nova requests resize-style confirmation, confirm with the resize
   confirm command and note that it was required.
3. After migration assert: destination host differs from the recorded source
   host, P3, P4 unchanged, P1 with the same recorded policy UUID, and P2
   against the destination.

## Test 4: live migration

Purpose: exercise the Nova adapter path in
`compute_post_live_migration_at_destination`, the historical failure point.
The adapter is out-of-tree on the compute nodes, so the compute logs in the
Nova log validation section are mandatory evidence for this test, not an
optional extra.

Run from the overseer with admin credentials:

```bash
openstack --os-cloud default server migrate \
  --live-migration \
  --wait "$SERVER"
```

Then:

1. Assert final state: P3, and source and destination hosts differ.
2. Inspect the migration record:

   ```bash
   openstack --os-cloud default server migration list \
     --server "$SERVER" -f json
   openstack --os-cloud default server event list "$SERVER" -f json
   openstack --os-cloud default server event show \
     "$SERVER" <request-id> -f json
   ```

   Assert the migration status is `completed` and every event reports
   `Success`, specifically `compute_post_live_migration_at_destination`.
3. Assert on ports: P2 against the destination, P1 with the recorded
   policy UUID.
4. Run the Nova log validation on **both** source and destination compute
   pods for the recorded request id.

## Nova log validation

Identify compute pods and their nodes, then grep both ends for the server
UUID, the request id, and adapter failures:

```bash
kubectl -n openstack get pods -o wide | rg 'nova-compute|NAME'

kubectl -n openstack logs <source-compute-pod> \
  -c nova-compute --since=20m |
  rg '<server-uuid>|<request-id>|NotImplementedError|<flavor-qos-adapter>'

kubectl -n openstack logs <destination-compute-pod> \
  -c nova-compute --since=20m |
  rg '<server-uuid>|<request-id>|NotImplementedError|<flavor-qos-adapter>'
```

Replace `<flavor-qos-adapter>` with the deployed out-of-tree adapter module
name (discover it on the compute pod configuration; it is not part of this
repository).

Hard failures:

- `NotImplementedError` on either compute.
- Any exception traceback originating from the flavor QoS adapter.
- Failed `compute_post_live_migration_at_destination`.
- Server ending in `ERROR`.
- Port bound to the wrong host.
- Missing or incorrect `qos_policy_id`.

Known-benign signals (record, do not fail): `network-vif-plugged` timing
warnings and transient placement allocation warnings appeared in a run whose
migration, placement cleanup, server state, port binding, and QoS state all
completed correctly.

## Optional data-plane validation

When throughput validation is required, take a floating IP from the
predefined DFW.dev pool and attach the three required security groups.
Discover available pool members at run time — take only a row with no Fixed
IP and no Port — and return the floating IP to the pool afterwards:

```bash
openstack --os-cloud dfw-dev-me floating ip list \
  -c ID -c "Floating IP Address" -c "Fixed IP Address" -c Port -f table

openstack --os-cloud dfw-dev-me server add security group "$SERVER" ssh-in
openstack --os-cloud dfw-dev-me server add security group "$SERVER" ping-in
openstack --os-cloud dfw-dev-me server add security group "$SERVER" iperf3

openstack --os-cloud dfw-dev-me server add floating ip \
  "$SERVER" <pool-floating-ip>
```

Validate ICMP reachability, SSH availability, iperf3 egress throughput
before and after a resize or migration, and that egress clamps to the
applied policy's configured egress limit (see the rate conversion table in
the tool README: `lite` 1,000,000 kbps, `plus` 2,000,000, `pro` 3,000,000,
`elite` 4,000,000).

The pool is smaller than the test pool, so associate one floating IP at a
time and remove or return it before the next fixture.

## Run log

Record for every test: run date, operator, server UUID and flavor, derived
port UUID(s), source and target policy UUIDs and names, request ids, source
and destination hosts, each predicate result, and any warnings recorded (for
example stale migration rows). This log is the artifact of the validation;
the procedure itself intentionally contains no environment-specific values.
