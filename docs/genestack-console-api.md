# The console HTTP API

The web page, a script, and the Apple apps all call the same API. It is served by the console on the deploy host, at `/api/v1`. This page is the map of that API. The path-by-path reference is the OpenAPI document on a running console, at `/swagger`, and the [API reference](https://github.com/PIndustries/genestack-console/blob/main/API_REFERENCE.md){:target="_blank"} in the console repository.

The install chapter is [Genestack Console](genestack-console.md). The jobs the API queues are [Console jobs](genestack-console-jobs.md). How one of those jobs is claimed and run is [How a job runs](genestack-console-runtime.md).

## How a call is authenticated

Two logins work at the same time. Each login is its own session. Logging out of one leaves the other in place.

The console is an OAuth 2 authorization server. `GET /.well-known/oauth-authorization-server` lists the endpoints.

- `POST /api/v1/oauth/token` issues the tokens. Send a form body.
  - `grant_type=password` with `username` and `password` is a login. The response is `access_token`, `token_type` (`Bearer`), `expires_in`, and `refresh_token`.
  - `grant_type=refresh_token` posts that login's refresh token. It does not need the access token. The response is a new access token and a new refresh token for that same login. The refresh token you just sent stops working. The other login is left alone. An unknown, expired, or reused refresh token is refused. That refusal does not drop the other login.
  - `grant_type=authorization_code` exchanges a code from the authorization endpoint. Send `client_id`, `redirect_uri`, and the PKCE verifier `code_verifier`. The code works once.
- `GET /api/v1/oauth/authorize` starts that code grant. Send `response_type=code`, `client_id`, `redirect_uri`, `state`, `code_challenge`, and `code_challenge_method=S256`. The person signs in on that page. The browser comes back to `redirect_uri` with `code` and `state`. `redirect_uri` is this console's `/ui`, or a loopback address for a program on the same machine.
- `POST /api/v1/oauth/revoke` drops the session for the access token or the refresh token you send. The other login stays. An unknown token still gets an empty success.
- `POST /api/v1/oauth/introspect` says whether a token is still active. The caller must already be signed in.
- The access token lasts 12 hours, from `auth.session_ttl_hours`. Send it as a Bearer token. The refresh token lasts `auth.refresh_ttl_hours` hours. The default is 168, which is 7 days. After that, the person signs in again. The only scope is `console`.
- `POST /api/v1/auth/login` and `POST /api/v1/auth/refresh` issue the same session for a client that already calls them. The login response includes `access_token` and `token_type` as well as `token`. `POST /api/v1/auth/logout` drops that session. `GET /api/v1/auth/whoami` says who you are, whether you are a platform admin, and which tenants you belong to.
- An API key from `config.yaml` is sent as `X-API-Key`. It is a platform admin. It skips tenant checks. Use it when the user accounts cannot be used. An API key is not an OAuth token and has no refresh token.

A route that names an environment checks your membership in that environment's tenant. A viewer can read. An operator can run the jobs marked for an operator. An admin can change the tenant and run the install. A person from another tenant is refused.

`GET /health` does not ask who you are. The agent install script does not either. Everything under `/api/v1` that reads a cloud does.

## Where the routes are registered

`app/main.py` attaches the routers. The order in that file is the order below. Each area is one file in `app/routers/`.

### Probes and the page

| File | What it serves |
| --- | --- |
| `app/routers/health.py` | `GET /health`. No login. |
| `app/routers/update.py` | Whether a newer console release is published, and `GET /api/v1/update/feed` for the release notes and the public pipeline. The check reads `update.url` in `config.yaml`. The default in the program is the `version.json` file on the GitHub Release. A viewer can read both. The running console installs a newer build when `update.watch` is on and no job is queued or running. |
| `app/routers/ui.py` | The web page at `/ui`, and `/docs` on the console itself. |
| `app/routers/agents.py` | The agent install script, unauthenticated, and the agent API. The install script is the curl the remote machine runs. The agent then connects out. |
| `app/routers/reach.py` | WireGuard, Tailscale, and Cloudflare Tunnel on this deploy host, and the address used for one environment. A platform admin saves the hub. An operator attaches an environment. Private keys, auth keys, and tunnel tokens are not returned. A WireGuard client config is returned once, when the peer is created. |
| `app/routers/database.py` | Copy this console's database between SQLite and Postgres. A platform admin reads the engine and the masked URL, or moves every table onto an empty target and writes `database_url`. The console must be restarted. The password is not returned. |
| `app/routers/traces.py` | Spans of this process and of modules people add. `GET /api/v1/traces` and `POST /api/v1/traces`. Admin only. The buffer is in memory and a restart clears it. No tokens. |

`GET /` redirects a browser to `/ui`.

### Accounts, environments, and jobs

| File | What it serves |
| --- | --- |
| `app/routers/auth.py` | Login, refresh, logout, whoami, and the optional company login. |
| `app/routers/oauth.py` | OAuth 2 authorize, token, revoke, introspect, and the discovery document. |
| `app/routers/tenants.py` | Tenants and memberships. |
| `app/routers/environments.py` | Create and list environments. An environment is one cloud. `GET /api/v1/environments/{id}/registry` lists the pull-through caches and Helm charts. A viewer can read it. `PUT` on that path saves the pull address, the registry list, and extra images to cache. Genestack's own images stay and are not stored on the environment. An operator can save it. Saving does not start a job. |
| `app/routers/envconfig.py` | The settings document for one environment, and its older versions. Saving does not edit `/etc/genestack` by itself. A job copies the document onto the deploy host. |
| `app/routers/overlays.py` | Network overlays saved on the environment. |
| `app/routers/operations.py` | `GET /api/v1/operations`, the catalog. |
| `app/routers/jobs.py` | Queue a job, read its status, read its log. |
| `app/routers/audit.py` | The audit log: who did what. |

The first admin is created from the install, or with `python -m app.cli`. The CLI can create a tenant, create a user, and add a member.

### Bare metal

| File | What it serves |
| --- | --- |
| `app/routers/baremetal.py` | The servers the console will boot, under `/api/v1/environments/{id}`. |
| `app/routers/pxe.py` | DHCP and boot-file prep, the rendered files, and a restart of that service. |
| `app/routers/discovery.py` | Servers and management ports found by a scan, before you accept them. |
| `app/routers/ilo_console.py` | The serial console on a management port. The management port is the BMC, iLO, or iDRAC. |

The boot order, and why the console is the DHCP server, is on the [install chapter](genestack-console.md).

### What the page reads

| File | What it serves |
| --- | --- |
| `app/routers/descriptor.py` | One description of the environment: where it is in the install. |
| `app/routers/workflow.py` | The guided steps. Six steps, from an empty environment to a cloud that answers. |
| `app/routers/fleet.py` | A short row per environment for the fleet screen. It does not probe the cluster on that request. |
| `app/routers/observe.py` | Logs and the observe view. |
| `app/routers/obs_proxy.py` | A proxy to a dashboard that is already installed in the cluster. |
| `app/routers/livestate.py` | The latest snapshot the collector wrote. |
| `app/routers/stream.py` | A server-sent stream of job and alert events. The page uses it instead of polling every row. |
| `app/routers/alerts.py` | Alert rules and the events they fired. |
| `app/routers/notify.py` | Saved Slack, Discord, Teams, Resend, and Twilio credentials. A viewer can list the name. An admin can save. The secret is not returned. |
| `app/routers/metrics.py` | Metric samples the collector stored. |

### This repository, and providers

| File | What it serves |
| --- | --- |
| `app/routers/genestack_services.py` | Reads this checkout: scripts, components, pipeline stages. Also registered on `app/main.py` as `/api/v1/genestack/scripts` and `/api/v1/genestack/components`. |
| `app/routers/state.py` | Exported state. |
| `app/routers/ovh.py` | An OVH account, the dedicated servers it can see, and adopting them into the environment. |
| `app/routers/hardware_accounts.py` | A hardware account for another provider, and its Terraform state. |

### After the cloud is up

| File | What it serves |
| --- | --- |
| `app/routers/k8s.py` | Kubernetes nodes, namespaces, and pods. The call uses the kubeconfig stored for that environment. |
| `app/routers/platform.py` | Talos and Kubernetes day-2 actions. These queue the platform jobs. |
| `app/routers/vms.py` | OpenStack instances. |
| `app/routers/cloud.py` | The rest of the OpenStack read and action surface the page uses. |
| `app/routers/novnc.py` | The noVNC session for an instance console. |
| `app/routers/apps.py` | Applications the console can deploy onto the cloud. |
| `app/routers/app_hooks.py` | Hooks those applications call back. |
| `app/routers/hostvms.py` | Virtual machines on the console host. Not OpenStack instances. |
| `app/routers/terminal.py` | A shell on the deploy host, or on a host the environment can SSH to. Ubuntu installed from here uses the `ubuntu` login and this environment's key. |
| `app/routers/native.py` | The API the Apple apps use, once the account page has opened this console. |
| `app/routers/native_kubernetes.py` | The Kubernetes calls in that same shape. |
| `app/routers/native_consoles.py` | The console sessions in that same shape. |

The native routes are on the console because the apps talk to the console after sign-in. They do not put a copy of the console on `my.genestack.dev`.

## A change is a job

A read returns JSON now. A change that takes time is `POST` a job. The response is the job id. You read `/api/v1/jobs/{id}` for status and the log. The worker runs the operation named in the body. The operation ids are on the [jobs page](genestack-console-jobs.md).

A second job that changes the same environment is refused while one is still queued or running. The response is HTTP 409, and it names the job that holds the environment. If the cluster is down, a Kubernetes read fails. The console can still accept a power job and an install job. Those do not go through the cluster.
