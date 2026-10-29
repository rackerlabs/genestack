!!! banner "TECH PREVIEW"

# Accessing a Trove Guest VM

Sometimes you need shell access to the VM behind a Trove database instance — to inspect the
MySQL container, read the guest agent log, or debug why an instance is stuck. Trove guest VMs
are intentionally not directly reachable: they sit on the `trove-mgmt-net` management overlay
and have no floating IP. Genestack ships `scripts/trove-guest-ssh.sh` to bridge that gap.

This guide explains how to use the script and how it works under the hood.

## Why direct SSH does not work

A Trove guest VM's only management interface lives on `trove-mgmt-net`, a geneve overlay with
no external gateway for inbound access. There is no floating IP and no route from the jump
host to the guest's management IP. The only place that can reach the guest's management IP
directly is the **compute node hosting it**, and only from inside the OVN metadata network
namespace for that network.

`trove-guest-ssh.sh` automates that path: it resolves the instance's Nova server and compute
host, then performs a two-hop SSH — first to the compute node, then from inside the OVN
metadata namespace into the guest.

## Prerequisites

Run the script from the Genestack jump host / launcher node, where:

- The genestack `openstack` CLI works and `/opt/genestack/scripts/genestack.rc` is present.
- `jq` is installed (used to parse the guest's address).
- Your SSH key at `~/.ssh/id_rsa` can log into the compute nodes as the `ubuntu` user.
- The Trove guest SSH key has been distributed to the compute nodes at
  `~/.ssh/trove_ssh_key`. This is done automatically by the enablement role's
  `trove_ssh_key_distribute` step (see the [Deploy Trove](openstack-trove.md) guide). Without
  it the second hop into the guest will fail.

## Usage

The script takes the Trove **instance ID** (or name) as its first argument. With no further
arguments it opens an interactive shell; any trailing arguments are run as a command inside
the guest.

!!! example "Open an interactive shell in the guest"

    ``` shell
    /opt/genestack/scripts/trove-guest-ssh.sh <INSTANCE_ID>
    ```

!!! example "Run a one-off command in the guest"

    ``` shell
    /opt/genestack/scripts/trove-guest-ssh.sh <INSTANCE_ID> ls -alh /etc/mysql
    ```

!!! example "Show help"

    ``` shell
    /opt/genestack/scripts/trove-guest-ssh.sh -h
    ```

You can find the instance ID with:

``` shell
openstack database instance list
```

Before connecting, the script prints the target it resolved so you can confirm you are hitting
the right VM:

``` text
target:
  instance = <instance-id>
  server   = <nova-server-id>
  node     = <compute-host>
  guest_ip = <trove-mgmt-net-ip>
  command  = <interactive shell>
```

### Interactive vs. command mode

- **No command** → the script requests a TTY (`ssh -tt`) and drops you into an interactive
  shell as the `debian` guest user.
- **With a command** → the script skips the TTY so stdout/stderr and the guest command's exit
  code propagate cleanly back to your terminal, making it safe to use in scripts.

!!! warning "Quoting complex commands"

    The command you pass is re-parsed by *three* shells: your local shell, the compute-node
    shell, and the guest shell. The script passes it through as-is, so you are responsible for
    quoting/escaping anything non-trivial (pipes, redirections, globs, quotes) so it survives
    all three layers. For anything complicated, prefer an interactive shell.

## What the script does

At a high level the script performs these steps:

1. **Pins the OpenStack config** — saves the current `OS_CLIENT_CONFIG_FILE`, points it at
   `~/.config/openstack/clouds.yaml`, and restores it on exit via an `EXIT` trap. It defaults
   `OS_CLOUD` to `default` and sources `/opt/genestack/scripts/genestack.rc`.
2. **Resolves the management network** — looks up the `trove-mgmt-net` network ID, which names
   the OVN metadata namespace (`ovnmeta-<network-id>`) on the compute node.
3. **Resolves the Nova server** — `openstack database instance show <id>` gives the
   `server_id`. If the instance has no server yet (still `BUILD`) the script exits with a
   helpful message.
4. **Resolves the compute host** — `openstack server show <server_id>` reads
   `OS-EXT-SRV-ATTR:host` to find which compute node is hosting the VM.
5. **Resolves the guest IP** — reads the server's address on `trove-mgmt-net` (via `jq`).
6. **Builds the inner SSH command** — the command to run *on the compute node* enters the OVN
   metadata namespace and SSHes into the guest:

    ``` shell
    sudo ip netns exec ovnmeta-<trove-mgmt-net-id> \
      ssh -tt -i ~/.ssh/trove_ssh_key \
          -o StrictHostKeyChecking=no \
          -o UserKnownHostsFile=/dev/null \
          debian@<guest-ip> [-- <command>]
    ```

7. **Performs the outer SSH** — connects from the jump host to the compute node as `ubuntu`
   using `~/.ssh/id_rsa`, and runs the inner command:

    ``` shell
    ssh -tt \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o IdentitiesOnly=true \
        -o IdentityFile=~/.ssh/id_rsa \
        ubuntu@<compute-host> "<inner command>"
    ```

The `-tt`/TTY option is included only in interactive mode, as described above.

### The two-hop path

``` text
 jump host                compute node (ubuntu)           guest VM (debian)
┌───────────┐  ssh id_rsa ┌────────────────────┐  ssh    ┌───────────────┐
│ you run   │────────────▶│ ip netns exec      │  trove_ │ debian@guest  │
│ the script│             │ ovnmeta-<net-id>   │──key───▶│ trove-mgmt-net│
└───────────┘             └────────────────────┘         └───────────────┘
```

### Identities and host-key handling

- **Outer hop** uses `~/.ssh/id_rsa` with `IdentitiesOnly=true` so only that key is offered to
  the compute node.
- **Inner hop** uses `~/.ssh/trove_ssh_key` (the distributed Trove guest key) as the `debian`
  user.
- Both hops set `StrictHostKeyChecking=no` and `UserKnownHostsFile=/dev/null` because guest
  IPs are ephemeral and reused across instances — this avoids host-key prompts and stale
  `known_hosts` conflicts. That is convenient for a management network you already control, but
  it does mean the connection is not verified against a pinned host key.

## Common tasks inside the guest

Once you have a shell (as the `debian` user), useful things to check:

``` shell
# The database runs as a container — inspect it
sudo docker ps
sudo docker logs database        # container is typically named "database"

# Trove guest agent log
sudo tail -f /var/log/trove/guest-agent.log

# Datastore image loader units (see the MySQL Images guide)
systemctl status trove-load-datastore-images.service
systemctl status trove-load-backup-image.service

# MySQL client into the running datastore container
sudo docker exec -it database mysql
```

## Troubleshooting

- **`could not look up trove instance <id>`** — the instance ID/name is wrong, or your CLI
  credentials cannot see it. Confirm with `openstack database instance list`.
- **`instance <id> has no server_id yet (still BUILD?)`** — the VM has not been created yet.
  Wait for the instance to leave `BUILD`, then retry.
- **`could not determine guest IP` / `compute host`** — the server may be in an error state or
  not attached to `trove-mgmt-net`. Check `openstack server show <server_id>`.
- **Permission denied on the second hop** — the Trove guest key is missing on the compute node.
  Re-run the enablement role's SSH key distribution:

    ``` shell
    cd /opt/genestack/ansible/playbooks
    ansible-playbook trove-enablement-techpreview.yaml --tags trove_ssh_key_distribute
    ```

- **Permission denied on the first hop** — your `~/.ssh/id_rsa` is not authorized on the
  compute node as `ubuntu`, or the compute host name did not resolve. Verify you can
  `ssh ubuntu@<compute-host>` directly.
- **`sudo: a password is required` inside the netns step** — the `ubuntu` user on the compute
  node needs passwordless `sudo` for `ip netns exec` (the standard Genestack node
  configuration provides this).

## Related documentation

- [Deploy Trove](openstack-trove.md) — full enablement flow, the management overlay network,
  and the `trove-mgmt-bridge`.
- [Building MySQL Images for Trove](openstack-trove-mysql-images.md) — what runs inside the
  guest VM.
