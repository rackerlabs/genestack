# Console jobs

A job is one operation on one environment. You start it from the web page or from `POST /api/v1/jobs`. The worker on the deploy host runs it. This page is the list of operations that ship with the console, and the shape of one you add.

The install chapter is [Genestack Console](genestack-console.md). How the process is split is [The console program](genestack-console-program.md). How a queued job is claimed and where the command runs is [How a job runs](genestack-console-runtime.md). The binary named on the install chapter is `v2026.10.03`. This list is the source on `main`.

## How a job is found

Each operation is a Python file under `app/modules/`. The folder is one area. The folder's `__init__.py` is a class that lists the files, in order. It does not call them.

The file sets three names.

- `OPERATION` is the catalog entry. `id` is what the API shows, such as `genestack.deploy`. The entry also names the role that can run it, and the parameters.
- `HANDLERS` is the internal name. The runner looks that name up.
- `run` is the function. The runner passes itself, the job, the environment, a log function, and the parameters. The function returns a dict.

`app/services/job_runner.py` resolves the environment, the deploy host, the timeout, and whether the command runs on the console, over SSH, or through an agent. Then it calls `run`. A file can import helpers from `app/services`. It should not import the runner at the top of the file. The runner imports the modules, so that import loops. Import the runner inside `run` if a step needs a helper that lives on it.

`backend` on the catalog entry is one of `internal`, `genestack`, `ansible`, `baremetal`, or `agent`. A step that does not fit the others uses `internal`.

A duplicate operation id or handler fails at startup. A module you add cannot replace a built-in. Give it a new id.

Built-in ids keep the order in `app/modules/order.py`. Anything you add is appended. `GET /api/v1/operations` returns that catalog. The Catalog screen on the web page is the same list.

A second job that changes the same environment is refused while one is still queued or running. The API answers 409 and names the job that holds the environment. A dry run is a rehearsal: the job logs the command and does not apply it. An environment can force that, and a job can ask for it. A fresh `config.yaml` starts with dry run on.

## Console

These run on the console computer. They are not a cloud install.

| Id | File | What it does |
| --- | --- | --- |
| `internal.health` | `app/modules/console/internal_health.py` | Reports that the console process is up. |
| `console.release` | `app/modules/console/release.py` | Compiles the console to a Linux binary under `dist/` on this machine. An installed console still downloads the GitHub Release. |
| `console.backup` | `app/modules/console/backup.py` | Copies the console database. |
| `console.vacuum` | `app/modules/console/vacuum.py` | Compacts the SQLite database. |

## Genestack

These drive the checkout at `/opt/genestack`. A push writes the saved settings into `/etc/genestack`. A deploy then runs the pipeline. The pipeline is the ordered list of install scripts in `app/services/service_registry.py`.

| Id | File | What it does |
| --- | --- | --- |
| `genestack.config.push` | `app/modules/genestack/config_push.py` | Writes the saved settings onto the deploy host. |
| `genestack.deploy` | `app/modules/genestack/deploy.py` | Pushes the settings, then runs the pipeline. Admin. Required stages stop the job on failure. Optional stages warn and continue. Tempest is not in this job. |
| `genestack.pipeline.run` | `app/modules/genestack/pipeline_run.py` | Runs one stage of that pipeline. |
| `genestack.greenfield` | `app/modules/genestack/greenfield.py` | Destructive. Wipes the selected servers, boots Talos, then deploys OpenStack. An ISO is rejected here because it does not wipe the disks. Admin. |
| `genestack.talos.bootstrap` | `app/modules/genestack/talos_bootstrap.py` | Bootstraps a Talos cluster that is already in maintenance. |
| `genestack.host_prepare` | `app/modules/genestack/host_prepare.py` | Prepares the deploy host. |
| `genestack.host_setup` | `app/modules/genestack/host_setup.py` | Runs `ansible/playbooks/host-setup.yml`. That is the same role `bin/setup-hosts.sh` uses. |
| `genestack.components.desired` | `app/modules/genestack/components_desired.py` | Reads which OpenStack services the settings ask for. |
| `genestack.components.list` | `app/modules/genestack/components_desired.py` | Lists those services. Same file, second catalog entry. |
| `genestack.components.reconcile` | `app/modules/genestack/components_reconcile.py` | Diffs the saved component list against the Helm releases. The default is a plan. `apply=true` installs what is missing and uninstalls what is not desired. Protected core components are not uninstalled. |
| `genestack.service.enable` | `app/modules/genestack/service_enable.py` | Runs `bin/install-<service>.sh` for one discovered install script. |
| `genestack.services.list` | `app/modules/genestack/services_list.py` | Lists the services this checkout can install. |
| `genestack.scripts.list` | `app/modules/genestack/scripts_list.py` | Lists `bin/install-*.sh`. |
| `genestack.repo_scripts.list` | `app/modules/genestack/repo_scripts_list.py` | Lists the utility scripts the console is allowed to run. |
| `genestack.repo_script.run` | `app/modules/genestack/repo_script_run.py` | Runs one of those scripts. |
| `genestack.cluster.status` | `app/modules/genestack/cluster_status.py` | Reads cluster status from the checkout. |
| `genestack.smoke` | `app/modules/genestack/smoke.py` | Runs the short smoke checks. |
| `genestack.verify` | `app/modules/genestack/verify.py` | Runs the Genestack test suite. |
| `genestack.tempest` | `app/modules/genestack/tempest.py` | Runs Tempest. It is not part of deploy or greenfield. |
| `genestack.k8s_upgrade` | `app/modules/genestack/k8s_upgrade.py` | Upgrades Kubernetes through Kubespray. |
| `genestack.backup_mariadb` | `app/modules/genestack/backup_mariadb.py` | Backs up MariaDB. |
| `genestack.hyperconverged_lab` | `app/modules/genestack/hyperconverged_lab.py` | Deploys the single-machine lab. |
| `genestack.state.export` | `app/modules/genestack/state_export.py` | Writes rendered state back into a checkout of this repository. |
| `registry.mirror` | `app/modules/genestack/registry_mirror.py` | Pulls container images into the cluster cache. |

The pipeline stages, in order, are:

| Stage | What it runs |
| --- | --- |
| `hosts` | `bin/setup-hosts.sh` |
| `infrastructure` | `bin/setup-infrastructure.sh` |
| `operators` | The operators and platform charts: cert-manager, sealed-secrets, the database operators, memcached, MetalLB, Longhorn, TopoLVM, Envoy Gateway. |
| `cni` | kube-ovn. Its own control point. A daily OpenStack restack does not include it. |
| `core` | Keystone, Placement, Glance. |
| `compute-network` | Nova, Neutron, libvirt. |
| `platform-extras` | The optional OpenStack services, including Cinder, Horizon, Octavia, and Skyline. |
| `observability` | Grafana, Loki, Tempo, Prometheus, and the exporters. Optional. |
| `testing` | Tempest. Its own job, not part of deploy. |

`hosts` through `compute-network` are required. A failure there stops `genestack.deploy`. The optional stages warn and continue. `from_stage` and `until_stage` on the deploy job are the control points.

`genestack.greenfield` is the path that installs Talos and then OpenStack. For each selected server it network-boots a RAM disk, waits for one wipe report, then network-boots Talos once. `stop_after=commission` returns after the wipe. `stop_after=talos` returns when Talos is in maintenance and does not deploy OpenStack. A machine that is still running the old operating system is not deployed onto. The boot rules are on the [install chapter](genestack-console.md).

## Bare metal

These talk to the server and to the boot service. The management port is the BMC, iLO, or iDRAC. The MAC address is the hardware address of the network port DHCP is watching.

| Id | File | What it does |
| --- | --- | --- |
| `baremetal.node.register` | `app/modules/baremetal/node_register.py` | Records a server: MAC, management port, and address. |
| `baremetal.nodes.list` | `app/modules/baremetal/nodes_list.py` | Lists those servers. |
| `baremetal.bmc_scan` | `app/modules/baremetal/bmc_scan.py` | Scans a range for management ports. |
| `baremetal.node.power` | `app/modules/baremetal/node_actions.py` | Powers a server on, off, or cycles it. |
| `baremetal.node.pxe_boot` | `app/modules/baremetal/node_actions.py` | Asks the management port for one network boot. |
| `baremetal.node.next_boot` | `app/modules/baremetal/node_actions.py` | Sets the next boot to disk, commission, or Talos. |
| `baremetal.node.provision` | `app/modules/baremetal/node_actions.py` | Commission, then one Talos boot, for one server. |
| `baremetal.node.iso_boot` | `app/modules/baremetal/node_actions.py` | Puts an ISO in the management-port virtual CD when the network port cannot PXE. This is not the greenfield path. Greenfield rejects an ISO because an ISO does not wipe the disks. |

`node_actions.py` is one file because those five jobs share one body. Everything else is one operation per file.

## Ansible, OpenStack, and the platform

| Id | File | What it does |
| --- | --- | --- |
| `host.preflight` | `app/modules/ansible/host_preflight.py` | Runs the host preflight playbook. |
| `host.basic_ops` | `app/modules/ansible/host_basic_ops.py` | Runs the basic host playbook. |
| `ansible.playbook.run` | `app/modules/ansible/playbook_run.py` | Runs one playbook from the allow list. |
| `openstack.servers.list` | `app/modules/openstack/servers_list.py` | Lists OpenStack servers. |
| `openstack.server.start` | `app/modules/openstack/server_actions.py` | Starts one. |
| `openstack.server.stop` | `app/modules/openstack/server_actions.py` | Stops one. |
| `openstack.server.reboot` | `app/modules/openstack/server_actions.py` | Reboots one. |
| `openstack.server.delete` | `app/modules/openstack/server_actions.py` | Deletes one. |
| `platform.talos.reboot` | `app/modules/platform/talos_reboot.py` | Reboots a Talos node that is already installed. |
| `platform.talos.shutdown` | `app/modules/platform/talos_shutdown.py` | Shuts a Talos node down. |
| `platform.talos.reset` | `app/modules/platform/talos_reset.py` | Runs `talosctl reset`. The system disk is wiped by default. |
| `platform.talos.upgrade` | `app/modules/platform/talos_upgrade.py` | Upgrades one Talos node. |
| `platform.talos.upgrade_many` | `app/modules/platform/talos_upgrade_many.py` | Upgrades several. |
| `platform.talos.apply_config` | `app/modules/platform/talos_apply_config.py` | Applies a Talos machine config. |
| `k8s.node.drain` | `app/modules/platform/k8s_node_drain.py` | Drains a Kubernetes node. |
| `k8s.apply` | `app/modules/platform/k8s_apply.py` | Applies a manifest. |

The platform jobs are day-2. The server is already in the cluster. They are not how a server gets Talos the first time. That is the bare-metal path.

## Other areas

| Id | File | What it does |
| --- | --- | --- |
| `ovh.byoi.reinstall` | `app/modules/ovh/byoi_reinstall.py` | Reinstalls an OVH dedicated server from your image. |
| `ovh.vrack.attach` | `app/modules/ovh/vrack_attach.py` | Attaches a server to a vRack. |
| `hardware.terraform.plan` | `app/modules/hardware/terraform_actions.py` | Plans Terraform for a saved hardware account. |
| `hardware.terraform.apply` | `app/modules/hardware/terraform_actions.py` | Applies that plan. |
| `hostvm.list` | `app/modules/hostvm/hostvm_list.py` | Lists virtual machines on the console host. |
| `hostvm.start` | `app/modules/hostvm/power.py` | Starts one. |
| `hostvm.stop` | `app/modules/hostvm/power.py` | Stops one. |
| `hostvm.restart` | `app/modules/hostvm/power.py` | Restarts one. |
| `agent.status` | `app/modules/agents/status.py` | Reports whether the agent at a site is connected. |
| `agent.install` | `app/modules/agents/install.py` | Installs the agent. |
| `agent.command` | `app/modules/agents/command.py` | Runs one allow-listed command on a connected agent. |
| `app.deploy` | `app/modules/apps/deploy.py` | Deploys one application onto a cloud that is already up. |

## Add an operation

Make a folder with the same shape, or add a file to a built-in folder.

1. Copy the shape of a function file. Set `HANDLERS`, `OPERATION`, and `run`.
2. Use an operation id and a handler name that are not already in the tables above.
3. Add the file name, without `.py`, to the `functions` tuple in the folder's `__init__.py`.

A folder of your own subclasses `Module`, sets `name`, and lists the files. Point `config.yaml` at it. A relative path is from the directory of the config file.

``` yaml
modules:
  paths:
    - /opt/genestack-console/modules/hello
```

The console loads the built-in folders first, then each path, in order. Restart the console. You do not edit the runner.

A package in the same Python environment can register itself instead of a path, with the entry point group `genestack_console.modules`. The value is the `Module` subclass.

The worked example is `examples/modules/hello/` in the console repository. That folder is not loaded unless its path is set. The same layout, with the example written out, is [Modules](https://github.com/PIndustries/genestack-console/blob/main/docs/modules.md){:target="_blank"}.
