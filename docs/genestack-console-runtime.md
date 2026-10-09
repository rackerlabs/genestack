# How a job runs

[Genestack Console](genestack-console.md) records a job when you click. This page is what happens after that, on the deploy host. The binary named on the install chapter is `v2026.10.03`. These chapters describe the source on `main`, which can be ahead of that tag.

How the program is split is [The console program](genestack-console-program.md). The operation names are [Console jobs](genestack-console-jobs.md).

## Two processes

The installer starts two systemd units. Both use the same binary, the same `config.yaml`, and the same database.

| Unit | Command | What it does |
| --- | --- | --- |
| `genestack-console.service` | `genestack-console-linux-amd64 serve --host 127.0.0.1 --port 8080` | The API and the web page. |
| `genestack-console-worker.service` | `genestack-console-linux-amd64 worker --daemon --interval 5` | The jobs. It looks at the queue every 5 seconds. |

The API process does not run the install. It writes a row and returns. A long deploy stays in the worker, so the browser request is not held open for the length of the pipeline.

`CONSOLE_CONFIG` points at a different `config.yaml` when the file is not in the working directory. The installed working directory is `/opt/genestack-console`.

## What the API does with a click

1. The route checks the login. A session is a Bearer token from `POST /api/v1/auth/login`. An API key is the `X-API-Key` header. Passwords are stored as a PBKDF2-SHA256 hash. They are not encrypted with `secret_key`. The session life is `auth.session_ttl_hours`, 12 hours unless you change it.
2. A route that names an environment checks your membership in that environment's tenant. A person from another tenant is refused.
3. A read returns JSON from the database, or from the last snapshot the collector wrote.
4. A change calls `execute_operation` in `app/services/job_runner.py`. That inserts a job row with status `queued` and returns the job id. The default is not to run the job inside the request.
5. The worker claims the row with one update that succeeds only while the status is still `queued`. Two workers cannot take the same row.

A job that changes an environment is marked mutating in the catalog. A second mutating job for that environment is rejected while one is queued or running. The response is HTTP 409, and the body names the job that holds the environment. The guard is a row in `env_mutex`. The select-then-insert is backed by that row, so two requests at the same moment still leave one holder.

The worker has a second check. If a queued mutating job's environment already has a running mutating job, the worker leaves it queued and tries again on a later pass. That is the backstop. The API has already refused a second submission.

A dry run logs the command and does not apply it. `dry_run` in `config.yaml` is the default. An environment can override it. A job can ask for it. A fresh config starts with dry run on, so the first deploy you did not mean to run is a log.

Secret parameters are not written in the job row in the clear. The catalog marks them. The stored params show `***`. The real value is Fernet-encrypted in `secret_params` and merged back only in the worker, in memory, while the function runs.

You can cancel a job that is still queued or running. A job that has already finished answers 409. Between commands, the runner notices the cancel and stops. It does not kill a shell command that is already in the middle of a line.

## Where the command runs

`app/services/executors.py` picks one place for the commands of an environment. The order is fixed.

1. An agent, when one is enrolled for that environment and has checked in recently. The check is a database read, so the worker can make it without a live socket of its own.
2. SSH, when the environment has `deployer_ssh_host`. The command is `ssh -o BatchMode=yes -o ConnectTimeout=10`, then the remote command. Only the Genestack variables cross the SSH session. A kubeconfig that was decrypted for the job stays on the console. Cluster probes with kubectl and helm run on the console.
3. The console computer itself, when neither of those is set. That is the usual install: the console and `/opt/genestack` are on the same machine.

Before the function runs, `app/services/envcontext.py` builds the environment the command will see.

- `GENESTACK_BASE_DIR` is the checkout, `/opt/genestack` when you followed the install chapter.
- When the environment has a config directory, `GENESTACK_CONFIG` and `GENESTACK_OVERRIDES_DIR` point at it. That directory is `/etc/genestack` after `bootstrap.sh`.
- `ANSIBLE_INVENTORY` is set when that directory contains `inventory/`.
- `KUBECONFIG` is the environment's kubeconfig. An encrypted copy is written to a file with mode `0600` for the length of the job, then removed.

The operation file does not open SSH itself. It calls the runner. The runner calls the executor.

## The settings document

Each environment has one YAML document. Every save is a new row in `env_config_versions`. The current document is the latest row. Saving does not edit `/etc/genestack`. `genestack.config.push` renders the document onto the deploy host, then a deploy runs the scripts against that tree.

`app/services/envconfig.py` knows these top-level keys. A key it does not know is kept and warned about. It is not rejected.

| Key | What a push does with it |
| --- | --- |
| `provider` | Writes the `provider` file. Kubespray or Talos. |
| `servers` | Renders `inventory/inventory.yaml` from the roles on those servers. The deploy host is not a host in that inventory. |
| `components` | Merges into `openstack-components.yaml`. |
| `chart_versions` | Merges chart pins into `helm-chart-versions.yaml`. Charts you did not name are left as they were. |
| `helm_overrides` | Writes `helm-configs/<service>/console-rendered.yaml`. The filename is the console's, so it does not replace a file you maintain by hand. Helm reads every file in the directory. |
| `kustomize_patches` | Writes an overlay under `kustomize/<service>/overlay/`. |
| `group_vars` | Writes `inventory/group_vars/<group>/console-rendered.yml`. |
| `secrets` | Merges into `kubesecrets.yaml`. An existing secret is kept. A name that exists in both files takes the console's value. The file is on the deploy host only while the job is running. |
| `storage` | Cinder keys go to the Cinder group vars. A Ceph block renders the Rook overlay. |
| `network` | Not a file. The keys are environment variables on the install commands. |
| `talos` | Talos image and machine settings for the bootstrap. Not a file in `/etc/genestack` by itself. |
| `pxe` | DHCP and boot-file settings. Consumed by the boot service, not written as an inventory file. |
| `deploy` | SSH host, SSH user, and a dry-run flag for this environment. |

`GET /api/v1/environments/{id}/config/render` is the preview. The merge into an existing `helm-chart-versions.yaml` or `kubesecrets.yaml` happens at push time. The preview shows the document's own render.

A push does not delete a file for a section you left out. An absent section leaves the file that is already on disk.

## The pipeline

`genestack.deploy` pushes the document, then runs the stages in `app/services/service_registry.py`. The stage ids and which scripts they call are on the [jobs page](genestack-console-jobs.md).

`hosts` through `compute-network` are required. A failure there stops the job. `platform-extras` and `observability` are optional. A failure there is a warning, and the job continues. `testing` is Tempest. Deploy and greenfield do not run it. `genestack.tempest` does.

`from_stage` and `until_stage` limit which stages this run includes. `cni` is its own control point. A daily restack of OpenStack does not include kube-ovn.

`genestack.pipeline.run` is one stage. `genestack.service.enable` is one `bin/install-<service>.sh`. The allow list is every install script under the checkout except `service-template`.

The script headers are how the console learns a service name. `app/services/service_registry.py` reads `KEY="value"` lines at the top of `bin/install-*.sh`, then joins that with `helm-chart-versions.yaml` and `openstack-components.yaml`. A missing file is an empty list. It does not raise.

`genestack.components.reconcile` compares the desired list with the Helm releases. The default is a plan. `apply=true` enables what is missing, through `genestack.service.enable`, and helm-uninstalls a release that is not desired. Protected core components are not uninstalled. A dry run forces the plan.

## DHCP and the boot file

Where the deploy host is L2 with the servers, DHCP and the boot-file HTTP server run inside the console process. There is no separate DHCP daemon to install.

`app/services/pxe.py` writes the files. `app/services/pxe_runtime.py` serves them. After a write, the runtime reloads. The files live under the console data directory.

```
<data_dir>/pxe/dnsmasq.conf
<data_dir>/pxe/boot.ipxe
<data_dir>/pxe/assets/vmlinuz
<data_dir>/pxe/assets/initramfs.xz
```

A site that has its own agent gets a directory, `data/pxe/<agent_id>/`, rendered from that agent's `pxe_config`. `next_server` in that config is the address on the site's L2 network that serves the boot file. One agent is one L2 network.

The `pxe` section names the interface, the DHCP range, and `http_port`. DHCP listens on UDP port 67. Set `http_port` yourself. When the key is omitted, the in-process server uses 8088, and the URL written into the boot file uses 8080. Those are not the same number, and neither one is a reason to move the console page off 8080. Servers you have recorded get a DHCP reservation from their MAC address and the address you typed.

`app/services/bootselect.py` is the per-MAC choice. The commission image is a small system that runs from memory. It does not mount a disk. It clears the front of each fixed disk, so the old bootloader cannot win the next start, and it posts one report. Talos is served for that MAC only after the console accepts the report. Ubuntu is the other operating system. It installs that one machine from `data/pxe/ubuntu/<hostname>/` and does not require the commission wipe. You place the kernel and initrd at `data/pxe/ubuntu/vmlinuz` and `data/pxe/ubuntu/initrd`. A MAC you have not selected is sent back to its own disk.

The boot order, and why an ISO is rejected on the greenfield path, is on the [install chapter](genestack-console.md). `baremetal.node.iso_boot` is a different operation. It inserts an ISO into the management-port virtual CD when the network port cannot PXE. It is not the first boot of a reinstall.

## The management port

The management port is the BMC, iLO, or iDRAC. `app/services/redfish.py` is the client. Power, a one-time network boot, and the virtual CD go through it. The password is encrypted in the database with `secret_key`.

`app/services/ilo_console.py` opens the HTML5 remote console for an iLO. The page loads that session through the console, so the browser does not have to reach the management port on its own.

A scan for management ports, and a scan that finds servers before you accept them, lands in `discovered_bmcs` and `discovered_nodes`. Accepting a row creates a `baremetal_nodes` record. Until you accept it, the console does not boot it.

## Secrets

`app/services/crypto.py` encrypts with Fernet. The key is the SHA-256 of `secret_key`, not the string itself. Stored values start with `fernet:`. An older plaintext value still reads. Rotating `secret_key` means re-encrypting every stored secret. Back up `config.yaml` and the database together before you rotate it.

The same key covers kubeconfigs, management-port passwords, provider secrets, and notification credentials. User passwords are the exception. They are hashed, not encrypted.

The console database holds the secrets. HashiCorp Vault and OpenBao are not part of this console. 1Password is not the store.

The deploy host has `kubesecrets.yaml` only while a job is running. The push writes that file so the install scripts can read it. The job removes it when the job finishes. Success, failure, and cancel all remove it. The same step removes the backup copy of that file under `.console-backup`, the `.ssh` files that the push wrote under the Genestack config directory, the backup copies of those `.ssh` files, and a kubeconfig file this job created. That kubeconfig includes one `talosctl` wrote on the deploy host. A kubeconfig the job fetched is encrypted onto the environment with the same Fernet helper, then the file is removed. The cleanup does not use `rm -rf`. It does not remove `helm-chart-versions.yaml`, the inventory, the push manifest, backups of those other files, or the deploy host account's `~/.ssh`. A kubeconfig path that was already on the host is left in place. A dry run writes nothing and deletes nothing.

The console also stages a decrypted kubeconfig under its data directory for the length of the job, mode `0600`, and removes that copy when the job ends. A copy left behind by a crash is removed the next time the console starts.

Job logs pass through `app/services/logredact.py` so a secret that showed up in command output is masked before the log is stored.

The server refuses to bind anything other than loopback while `secret_key` and the API keys are still the built-in examples. The installed unit binds `127.0.0.1`. From a laptop, forward the port. Do not open 8080 on a public address to skip the forward.

## The collector, the stream, and alerts

The worker starts a collector thread unless you pass `--no-collector`. Every `collector.interval_seconds` (60 by default) it asks the cluster and writes a `cluster_snapshots` row. The page reads that row. The fleet request does not open Kubernetes.

A probe that hangs is cut off at `collector.probe_timeout_seconds` (15). Snapshot rows older than `collector.retention_hours` (168, a week) are dropped. If the cluster is down, the snapshot goes stale. Power and install jobs still run. They do not ask the cluster whether it is up.

Metric samples are off until `metrics.enabled` is set. When they are on, `app/services/metrics.py` stores `kubectl top` output. The default keep is 72 hours.

The event bus in `app/services/events.py` is inside one process. The worker is a different process, so a job update there does not reach the browser by itself. `app/services/relay.py` polls the database every few seconds and republishes new rows onto the API process. The page listens on the server-sent stream. On startup the relay notes the current high-water mark and does not replay old rows.

The browser cannot put an `Authorization` header on that stream, or on the terminal socket. It trades the session for a one-use ticket at `POST /api/v1/auth/ticket` and connects with `?ticket=`. The ticket is kept in memory for that API process. It is not written to the database.

Alert rules watch the snapshot. The conditions are a node that is not Ready, a pod in a crash loop, a failed probe, and a service that is down. A rule fires when the condition starts. It does not send a second message when the condition clears. On `main`, a rule can name a saved Slack, Discord, Teams, Resend, or Twilio channel. A missing or disabled channel is skipped. A webhook URL on the rule is checked again before it is called, so a saved URL cannot be pointed at a local address later.

Once a day, and once when the worker starts, `app/services/retention.py` prunes. The defaults are 30 days of jobs, 90 days of audit rows, 7 days of agent commands, 30 days of alert events, and 50 saved config versions per environment.

## The agent

The agent is a separate program in `agent/`. It is not the console. You install it on a computer that is L2 with a site the deploy host cannot reach. It dials out. It does not listen for you to connect in.

It needs two environment variables. `GSC_HUB_URL` is the console WebSocket address. `GSC_AGENT_TOKEN` is the one-time enrollment token the console printed. The raw token is shown once. The database stores the SHA-256. The agent answers an HMAC challenge with the token, then sends heartbeats. Use `wss://` so that token is not on an open network.

The console holds the WebSocket in the API process. The worker is a different process, so it cannot write to that socket. A command or a file for the agent is a row in `agent_commands`. `app/services/agent_relay.py` claims the row and forwards the frame. The states are pending, dispatched, then done, failed, or timed out. An environment with no connected agent fails immediately.

`agent.command` runs one of a fixed list: `uptime`, `hostname`, `ip addr`, `talosctl version`, `kubectl get nodes`, `ls /etc/genestack`. There is no general shell. A file write is confined to `GSC_ALLOWED_ROOT`, which defaults to `/etc/genestack`. A push or a deploy, when the executor is the agent, sends each rendered file that way. The agent writes it, mode `0644`, after backing up the file that was already there.

The agent also reports what it sees. `GSC_PXE_LEASES` is an optional path to a dnsmasq lease file. A new lease is a `pxe_request` event. A BMC sweep is a `bmc_found` event. Both land in the discovery inbox. You accept a row before the console will boot that server. You still start the job from the console.

`hub.advertise_url` in `config.yaml` is the address the agent is told to use when the console's own bind address is loopback. The agent has to be able to open that address. The console does not open an inbound path to the site.

## config.yaml

One file. `python -m app.cli make-config` prints a new one, with a generated `secret_key` and generated API keys. The keys that change how the program behaves:

| Key | Default | What it does |
| --- | --- | --- |
| `server.host`, `server.port` | `127.0.0.1`, `8080` in the installed unit | Where the page listens. The code default, if the file omits the host, is every interface, and startup refuses that while the secrets are still the examples. |
| `secret_key` | a public example string | Fernet key for secrets in the database. Replace it. |
| `auth.api_keys` | example keys | Break-glass platform admins, sent as `X-API-Key`. Replace them. |
| `auth.session_ttl_hours` | 12 | Session life. |
| `auth.dev_auto_login` | false | Every request is a platform admin, with no password. Leave it off on a machine that is not your laptop. |
| `dry_run` | true | Jobs log commands and do not apply them. |
| `database_url` | `sqlite:///./data/console.db` | Postgres when you set a Postgres URL. |
| `data_dir` | `./data` | Database, PXE files, and the backup live under here. |
| `genestack.root` | empty, then auto-detect | The checkout. `/opt/genestack` when you followed the install chapter. |
| `modules.paths` | empty | Extra operation folders. Loaded after the built-ins. A relative path is from this file's directory. |
| `job_timeout_seconds` | 600 | Used when the operation does not name its own timeout. `genestack.deploy` and `genestack.greenfield` allow 21600 seconds. `genestack.pipeline.run` allows 14400. |
| `collector.*` | on, every 60 seconds | Snapshots. Set `collector.enabled` false to stop them. |
| `retention.*` | see the section above | How long rows are kept. |
| `oidc` | off | Company login. `https://my.genestack.dev` is one issuer you can point this at. People on the deploy host can still use a local user. |
| `update.url` | the GitHub Release `version.json` | Where the console looks for a newer build. `config.yaml.example` still names `https://genestack.dev/releases/version.json`. The value in the file you installed is the one that is checked. `update.auto` applies a downloaded build only when you turn it on. |
| `hub.advertise_url` | empty | The address agents dial. |
| `ovh` | empty | The application key for listing OVH dedicated servers. The per-environment consumer key is created in the console and is not stored in this file. |
| `seed_demo` | false | A labeled sample tenant so the page has something to click. The machines in it are not real. The installer can turn this on for a first run. |

An older file that still has a `maas` block still loads. The console does not use it. The next save drops the block.

## The command line

`python -m app.cli` talks to the local database. It does not open the web page.

| Command | What it does |
| --- | --- |
| `make-config` | Prints a config file with new secrets. |
| `create-tenant` | Creates a tenant. |
| `create-user` | Creates a person. `--platform-admin` is the break-glass user, not a tenant role. |
| `add-member` | Puts that person in a tenant as viewer, operator, or admin. |
| `create-env` | Creates an environment. |
| `list-ops` | Prints the catalog. |
| `seed-demo` | Fills the sample tenant. |
| `health` | Prints the local settings. It does not start the server. |

The worker is `python -m app.worker.runner`, or the `worker` subcommand of the binary. `--once` is the default and drains one batch. `--daemon` is what systemd runs. `--check` confirms the worker can read the database, then exits. That is the container health check.

## The rest of the tree

| Path | What it is |
| --- | --- |
| `app/routers/` | The HTTP routes. The map is [The console HTTP API](genestack-console-api.md). |
| `app/modules/` | One file per operation. The list is [Console jobs](genestack-console-jobs.md). |
| `app/static/js/pages/` | The screens. The map is [The console web page](genestack-console-ui.md). |
| `agent/` | The outbound agent. |
| `examples/modules/hello/` | A module in the same shape as the built-ins. It is not loaded unless `modules.paths` names it. |
| `ansible/` | The playbooks `host.preflight`, `host.basic_ops`, and `ansible.playbook.run` are allowed to call. |
| `terraform/` | Plans for a hardware account on Rackspace, AWS, Azure, or GCP. `hardware.terraform.plan` and `hardware.terraform.apply` run them. The state is stored encrypted on the hardware account. |
| `scripts/systemd/` | The two unit files. |
| `pxe/` | A small container, dnsmasq plus a static HTTP server. A container install can add it with `GSC_WITH_PXE=1`. The Linux binary serves DHCP and the boot files in-process and does not start that container. The files are the ones `app/services/pxe.py` writes. |

The account page and the Apple apps are not in this tree. They open the console you installed. The environment and the job log stay in the console database on the deploy host.
