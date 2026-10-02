# Genestack Console

Genestack is this repository: the scripts, Ansible, and charts that install OpenStack on Kubernetes. Genestack Console is a separate program you install on the same Linux computer as this checkout. It is the browser page and the job runner for the work those scripts already do.

That computer is the deploy host. Pick a machine that can reach the servers you are installing. The console, the saved settings, the job log, and the passwords for the server management ports stay on it. The UI is `http://127.0.0.1:8080/ui` on that machine. The first screen is Guided setup.

The console also answers DHCP on the server network and hands a server a boot file when you are installing it. DHCP is how a machine asks for an IP address. The boot file is what the network card downloads when the server is told to start from the network. A server you have not selected boots from its own disk. A server you select is wiped from a small in-memory system, then booted once into Talos. Talos is the operating system Kubernetes runs on for this bare-metal path. The deploy job then continues with the scripts in this repository. The steps are in [Bare metal](#bare-metal).

The console is its own project, with its own releases: [PIndustries/genestack-console](https://github.com/PIndustries/genestack-console){:target="_blank"}. The install matrix, the HTTP API, and the release notes live in that repository.

## Where the files go

Follow [Getting the code](genestack-getting-started.md) first. `bootstrap.sh` writes `/etc/genestack/provider`. Kubespray is the default Kubernetes provider. Talos is the other one, and the bare-metal path below uses the same maintenance-then-config order as [Talos Linux](k8s-talos.md).

| Path | What it is |
| --- | --- |
| `/opt/genestack` | This repository. The console runs the scripts from here. |
| `/etc/genestack` | Inventory, provider, and the overrides you already edit for Ansible. |
| `/opt/genestack-console` | The console install. It is next to the Genestack tree, not inside it. |
| `submodules/genestack-console` | The console source, pinned like Kubespray. |
| `127.0.0.1:8080` | The UI. It binds loopback until you change `server.host`. |

The pin is a submodule of [PIndustries/genestack-console](https://github.com/PIndustries/genestack-console){:target="_blank"} at release `v2026.10.03`. A normal clone skips it (`ignore = all`). Fetch it when you want the source next to this tree:

``` shell
git submodule update --init submodules/genestack-console
```

On the deploy host:

``` shell
ssh -L 8080:127.0.0.1:8080 <deploy-host>
```

Open `http://127.0.0.1:8080/ui`. The first screen is Guided setup. The first admin password is written to `/opt/genestack-console/ADMIN_CREDENTIALS.txt` with mode `0600`.

The published build for this page is [v2026.10.03](https://github.com/PIndustries/genestack-console/releases/tag/v2026.10.03){:target="_blank"}. The Linux file is `genestack-console-linux-amd64`. [`version.json`](https://github.com/PIndustries/genestack-console/releases/download/v2026.10.03/version.json){:target="_blank"} on that release points at the download. The console repository also documents this installer, which pulls from the console release channel:

``` shell
curl -fsSL https://get.genestack.dev/console.sh | bash
```

That URL redirects to the current GitHub Release asset `console.sh`.

Use the GitHub Release asset when you need the `v2026.10.03` binary specifically. Linux, WSL, and a Mac lab are covered in the console install guide. `config.yaml` and the console database hold users, sessions, and the encrypted BMC secrets. Back them up together. The database alone cannot decrypt those secrets.

## What you do in it

An environment is one cloud: a lab, a rack, or a region. It belongs to one tenant. Jobs and credentials stay inside that environment.

You point the environment at `/opt/genestack` and at the `/etc/genestack` directory `bootstrap.sh` already filled in. A saved config can be pushed to the deploy host. A deploy job then runs the install scripts and playbooks from this tree, with `GENESTACK_BASE_DIR`, `GENESTACK_CONFIG`, and the Ansible inventory. The job log is on that same environment.

After the cluster is up, the environment is where you read Kubernetes and run the namespace, node, and pod actions, run the OpenStack service workflows, and download the kubeconfig and talosconfig. Skyline is still the OpenStack dashboard for project users. The console is for the people operating the deploy.

Roles on the console are viewer, operator, and admin. API keys in `config.yaml` are the break-glass path.

## Bare metal

Each server has a management port (BMC, iLO, or iDRAC) and a port on the same network as the machine that serves DHCP. You enter both. The console powers the server through the management port. It matches the other port by MAC address when it hands out an IP and a boot file.

Each machine has its own next boot. **disk** is the default, including for a MAC you have never asked the console to install. The machine boots its local disk. **commission** is a small system in memory that wipes the fixed-disk headers and posts one report. **talos** is the Talos maintenance image, and the console will only serve it after that report has been accepted. Machine config is pushed after the wipe. It is not put on the kernel command line.

The machine loads a chain script first. The chain hands off to the file for that MAC, or it exits to the local disk. A machine that shows up on the provisioning network and was not selected is left alone.

For a machine you did select:

1. The console writes the commission script for that MAC and sends a one-shot PXE through the BMC.
2. The RAM disk wipes the fixed disks and posts one report. Posting the same report again does not start another wipe.
3. The console switches that MAC to Talos and PXE-boots it once.
4. Talos comes up in maintenance. The deploy job continues from the [Talos Linux](k8s-talos.md) flow.

An ISO cannot be the first boot of a reprovision. An ISO does not wipe the disks, so the console rejects `boot=iso` for this path.

DHCP and the boot files have to be on the same Ethernet network as the machines, with no router between them. If the deploy host is on that network, the console serves them. If the machines are on the other side of a firewall, put the console agent on that site. The agent opens a connection out to the console and serves DHCP and the boot files there. The agent install is in the console install guide.

!!! warning

    The wipe report has to reach the console. A server that only hands out the boot files will leave the machine on the commission image, because nothing accepts the report and switches the MAC to Talos.

!!! tip

    Stop the job after commission if you want to look at the wipe before Talos is served. Stop after Talos if you want maintenance mode and you do not want the job to continue into inventory and OpenStack.

## my.genestack.dev

`https://my.genestack.dev` is the account page for a console you already run. From there you manage the account, connect the Mac, iPhone, iPad, and Apple Watch apps to that console, and ask us for support. The apps sign in at the portal. The portal forwards the session to your console over the tunnel on the deploy host.

The portal does not run a copy of the console. There is no environment, job log, or BMC secret stored there. Everything you do to the cloud happens on the console at `/opt/genestack-console`. Operators on the deploy host can also sign in locally, with an API key, or with their own identity provider, and never touch the portal.

Issuer, redirect, and the `gsc_console` cookie are written up in [Connect a console to my.genestack.dev](https://github.com/PIndustries/genestack-console/blob/main/docs/hosted-mode.md){:target="_blank"}.

## The rest of the manual

| You need | Read |
| --- | --- |
| Install, systemd, Mac and WSL | [Install](https://github.com/PIndustries/genestack-console/blob/v2026.10.03/docs/install.md){:target="_blank"} |
| A local all-in-one lab | [Install AIO](https://github.com/PIndustries/genestack-console/blob/v2026.10.03/docs/install-aio.md){:target="_blank"} |
| Jobs, agents, and auth | [Architecture](https://github.com/PIndustries/genestack-console/blob/v2026.10.03/docs/architecture.md){:target="_blank"} |
| Portal account and the Apple apps | [Connect a console to my.genestack.dev](https://github.com/PIndustries/genestack-console/blob/main/docs/hosted-mode.md){:target="_blank"} |
| HTTP API | [API reference](https://github.com/PIndustries/genestack-console/blob/v2026.10.03/API_REFERENCE.md){:target="_blank"}, and `/swagger` on a running console |
| How a release is cut | [Releasing](https://github.com/PIndustries/genestack-console/blob/v2026.10.03/docs/releasing.md){:target="_blank"} |

!!! note

    This site is built from the `main` branch of Genestack. The console is released on its own tags. If this page and a console release disagree, use the console repository at that tag.
