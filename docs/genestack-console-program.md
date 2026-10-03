# The console program

[Genestack Console](genestack-console.md) is the program you install on the deploy host. This page is how that program is put together. The binary named on the install chapter is `v2026.10.03`. These chapters describe the source on `main`, which can be ahead of that tag. When a step and that binary disagree, follow the tag.

Genestack is this repository: the scripts, Ansible, and charts that install OpenStack on Kubernetes. The console is a different program. It lives in [PIndustries/genestack-console](https://github.com/PIndustries/genestack-console){:target="_blank"}. The Python package inside that repository is `app`.

## One process, and a worker beside it

The installed file is one Linux binary. That process does four jobs at once.

- It serves the web page at `127.0.0.1:8080`.
- It serves the HTTP API under `/api/v1`.
- It opens the console database.
- When the deploy host is L2 with the servers, it answers DHCP and serves the boot file. L2 means they are on one local network. DHCP is how a machine asks for an IP address. The boot file is the small program the network card downloads when the server starts from the network. Both run inside this process. The boot order is on the [install chapter](genestack-console.md).

A second process, the worker, runs the jobs. A job is one operation on one environment: push the saved settings, deploy, power a server, hand a server a boot file. The web request only records the job. The worker runs it, so a long install does not sit inside the browser request.

The worker is `app/worker/runner.py`. It takes the oldest queued job. Claiming a job is one database update that succeeds only if the row is still queued, so two workers cannot run the same job. A second job that changes the same environment is refused while one is still queued or running. The API answers 409 and names the job that holds the environment. A read, such as listing servers, is not held behind that lock.

The same worker also collects cluster snapshots and prunes old job logs, audit rows, sessions, and alert events. The collector runs on its own threads. A hung Kubernetes call does not stop the worker from picking up the next job.

## Where the source is

| Path | What it is |
| --- | --- |
| `app/main.py` | Starts the process and attaches every HTTP route. |
| `app/routers/` | One file per area of the API. A route checks who you are, then reads data or queues a job. |
| `app/services/` | The work those routes and jobs call. Boot files, the management port, inventory, alerts, and the bridge into this Genestack checkout all live here. |
| `app/modules/` | The jobs. One folder per area. One Python file per operation. The folder's `__init__.py` lists those files, in order, and does not call them. |
| `app/services/job_runner.py` | Prepares the environment, then calls the one function that matches the job. The steps are not written in the runner. |
| `app/modules/order.py` | The order the built-in operations keep in the catalog. An operation you add is appended. |
| `app/models.py` | The database tables. |
| `app/db.py` | Opens the database and adds any new column an older database does not have yet. There is no separate migration tool. |
| `app/static/js/pages/` | The web page, one file per screen. |
| `app/templates/ui.html` | The shell around those screens: the sidebar and the sign-in form. |
| `app/config.py` | Reads `config.yaml`. |
| `app/worker/runner.py` | The job worker. |
| `config.yaml` | Bind address, secret key, API keys, database, and any extra module folders. |

`app/services/genestack_bridge.py` is how the console reads this repository. It finds `/opt/genestack`, lists `bin/` scripts, reads `openstack-components.yaml`, and runs a pipeline stage. It does not copy this repository into the console.

## What a click becomes

1. The browser loads `/ui` from the deploy host. From a laptop that is an SSH forward, `ssh -L 8080:127.0.0.1:8080`.
2. The page calls `/api/v1`. A person uses a session. An emergency login uses an API key from `config.yaml` in the `X-API-Key` header.
3. The route checks the role. A viewer can read. An operator can run the day-to-day jobs. An admin can change accounts, delete, and run the install.
4. A read returns JSON. A change is stored as a job row and the worker runs it.
5. The job log is written on that row. The page reads the log back. The log stays on the deploy host.

An environment is one cloud: a lab, one rack, or one region. A tenant is the group of people allowed to use that cloud. Every environment belongs to one tenant. A person in another tenant gets a refusal, not an empty list.

## The database

The default database is SQLite, at `data/console.db` under the console directory (`/opt/genestack-console` when you used the installer). `database_url` in `config.yaml` can point at Postgres instead.

Passwords, kubeconfigs, management-port secrets, and notification credentials are encrypted before they are stored. The key is `secret_key` in `config.yaml`. Back up that file and the database together. A copy of the database without the file cannot be decrypted.

| Table | What it holds |
| --- | --- |
| `users`, `session_tokens` | People, and the login that expires. Passwords are hashed. They are not encrypted with the config key. |
| `tenants`, `memberships` | A tenant, and the role a person has there: viewer, operator, or admin. |
| `environments` | One cloud. The Genestack checkout path, the `/etc/genestack` path, the SSH host, and the encrypted kubeconfig. |
| `env_config_versions` | Each save of that cloud's settings. The current document is the latest version. |
| `jobs` | One operation, its parameters, its status, and its log. |
| `env_mutex` | The lock that keeps two changing jobs off the same environment. |
| `audit_log` | Who did what, and whether it worked. |
| `baremetal_nodes` | A server the console will boot: MAC address, management port, and the next boot. |
| `discovered_nodes`, `discovered_bmcs` | Servers and management ports found by a scan, before you accept them. |
| `ovh_accounts`, `hardware_accounts`, `terraform_state` | A provider login, and the Terraform state for a hardware account. The secret is encrypted. |
| `host_vms` | Virtual machines on the console host itself. These are not OpenStack instances. |
| `agent_credentials`, `agent_commands` | An agent enrolled at a remote site, and a command sent to it. |
| `cluster_snapshots`, `metric_samples`, `config_drift` | What the collector last saw, a few metric samples, and a difference between saved settings and the cluster. |
| `alert_rules`, `alert_events` | A rule, and the time it fired. |
| `notify_channels` | A Slack, Discord, Teams, Resend, or Twilio credential, encrypted. This table is on `main`. It is not in the `v2026.10.03` binary. |
| `apps` | An application the console can deploy onto a cloud that is already up. |

An older `config.yaml` that still has a `maas` block still loads. The console does not use it. The next save drops the block. Talos is installed by this program, from the network.

## Who can sign in

Three roles, and one emergency key.

- A viewer can read the environment, the job log, and the catalog.
- An operator can run the jobs the catalog marks for an operator. Powering a server and the day-to-day OpenStack actions are in that set.
- An admin can create people, change membership, save notification credentials, and run the install jobs. `genestack.deploy` and `genestack.greenfield` require admin.

An API key in `config.yaml` is a platform admin. It is the login you use when the user accounts cannot be used. It is not a tenant role. The server refuses to bind a non-loopback address while the secret key and the API keys are still the built-in examples.

A company login is optional. It is off until `oidc.enabled` is set. The account page at `https://my.genestack.dev` is a separate program. People on the deploy host can sign in with a local user and never open it.

## What the collector and the alerts do

The collector asks the cluster, on a timer, and writes a snapshot. The web page reads the snapshot. It does not open Kubernetes on each click. If the cluster stops answering, the snapshot goes stale and the console can still power the servers and run the install. It cannot invent a live answer from a cluster that is down.

An alert rule watches that snapshot. The conditions are a node that is not Ready, a pod in a crash loop, a failed probe, and a service that is down. The rule fires once when the condition starts. It does not send again when the condition clears. A rule can post to its own webhook URL. On `main`, it can also send through a saved channel. The channel is Slack, Discord, Teams, Resend, or Twilio. The secret is stored encrypted and is not returned after you save it. A missing or disabled channel is skipped. The webhook still fires.

## The agent

When the deploy host cannot be L2 with a site, install the console agent on a computer that is. The agent gives out addresses and boot files at that site and connects out to the console. You still start the job from the console. One console often looks after several sites this way.

The enrollment is `app/services/agents.py`. The install script the agent curls is served by the console. A command the console sends is allow-listed. The agent does not open an inbound port on the site for you to manage it. It dials out.

## What is not in this program

The Apple apps and `https://my.genestack.dev` are not in this repository and not in the console repository. The apps sign in on the account page. That page then opens the console you installed. The environment, the job log, and the management-port passwords stay in the console database on the deploy host. A job removes `kubesecrets.yaml`, and a kubeconfig it created, when the job finishes.

The next pages are [how a job runs](genestack-console-runtime.md), the [jobs](genestack-console-jobs.md), the [HTTP API](genestack-console-api.md), and the [web page](genestack-console-ui.md).
