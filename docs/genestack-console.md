# Genestack Console

Genestack Console is the operator console for a Genestack deploy host. You still build the cloud from this repository. The console is the place you run that work from: one environment per cloud, a versioned copy of `/etc/genestack`, jobs for the install scripts in this tree, and a view of Kubernetes, Talos, and OpenStack after the cluster is up.

This page is part of the deployment guide. It uses the same paths, the same provider choice, and the same Talos and Kubespray steps as the rest of this book. The longer manual, the HTTP API, and the release notes live in the console repository, because the console ships on its own tags.

## Where it sits

Clone this repository to `/opt/genestack`, as [Getting the code](genestack-getting-started.md) describes. The console runs beside that checkout. It does not replace `bootstrap.sh`, the inventory, or the provider file.

``` mermaid
flowchart TB
  operator[Operator]
  console[Genestack Console on the deploy host]
  tree["/opt/genestack — this repository"]
  etc["/etc/genestack — inventory, provider, overrides"]
  k8s[Kubernetes]
  os[OpenStack]
  pxe[Provisioning network]

  operator --> console
  console --> tree
  console --> etc
  tree --> k8s
  k8s --> os
  console --> pxe
  pxe --> k8s
```

A deploy host that can reach the machines is the normal place to run it. The UI listens on loopback. Reach it with an SSH tunnel when you are not on that host.

``` shell
ssh -L 8080:127.0.0.1:8080 <deploy-host>
```

Then open `http://127.0.0.1:8080/ui` and follow Guided setup.

## What you still do from this guide

The console calls the same steps an operator runs by hand. Read these pages first. The console is the runner, not a second cloud.

- [Getting the code](genestack-getting-started.md) puts the tree in `/opt/genestack` and the inventory in `/etc/genestack`.
- [What is Genestack?](deployment-guide-welcome.md) and [Architecture](genestack-architecture.md) are the cloud the console deploys.
- [Kubespray](k8s-kubespray.md) is the default Kubernetes provider after `bootstrap.sh`.
- [Talos Linux](k8s-talos.md) is the other provider. Bare-metal Talos from the console follows that layout: a maintenance boot, then config pushed to the node.

`bootstrap.sh` writes the provider into `/etc/genestack/provider`. Point the console environment at that same config directory. Jobs then see `GENESTACK_BASE_DIR`, `GENESTACK_CONFIG`, and the inventory you already keep for Ansible.

## What the console operates

An environment is one cloud: a lab, a staging rack, or a production region. Each environment belongs to one tenant. Jobs, credentials, and inventory stay inside that environment.

| Work | What you do in the console |
| --- | --- |
| Bring-up | Create the environment, set the Genestack root and `/etc/genestack` path, then Guided setup |
| Config | Save a versioned config document and push it to the deploy host |
| Deploy | Run the install scripts and Ansible playbooks from this repository, and watch the job log |
| Kubernetes | Read the cluster, and run the namespace, node, and pod actions for that environment |
| OpenStack | Run the service workflows against the cloud this tree deployed |
| Bare metal | Register the BMC, set the next boot for that machine, and PXE it |
| Access | Download the kubeconfig and talosconfig for the environment |

Membership roles are viewer, operator, and admin. API keys in the console config are the break-glass path. Day-to-day login is a user on that console, or the portal when you run hosted mode.

The console is the fleet control plane. Skyline remains the OpenStack dashboard for project users. Horizon and Skyline docs in this guide still apply to the cloud after it is deployed.

## Bare metal

Each machine has its own next boot:

- **disk** leaves the machine on its local disk. This is the default, including for a MAC the console has never been asked to install.
- **commission** boots a RAM disk, wipes the fixed-disk headers, and posts one report back to the console.
- **talos** boots the Talos maintenance image for that MAC. The console serves this only after a commission report has been accepted. Machine config is pushed after the wipe. It is not placed on the kernel command line.

The first file a machine loads is a chain script. That script hands off to the per-MAC file, or exits to the local disk. A stranger on the provisioning network is not wiped.

The order for a machine you chose to provision:

1. The console renders the commission script for that MAC and sends a one-shot PXE through the BMC.
2. The RAM disk wipes the fixed disks and posts one report. A second copy of the same report does not start another wipe.
3. The console switches that MAC to Talos and PXE-boots it once.
4. Talos comes up in maintenance. The deploy job continues from there, using the Talos flow in [Talos Linux](k8s-talos.md).

An ISO boot is rejected for this path. An ISO does not wipe the disks, so it cannot be the first boot of a reprovision.

PXE and DHCP have to sit on the same Layer 2 network as the machines. When the console host is on that network, the console serves DHCP and the boot files itself. When a site is on the far side of a firewall, install the console agent on that site. The agent dials out to the console and serves PXE there. The install guide in the console repository is the procedure for that agent, including the overlay address the console uses for it.

!!! warning

    The commission report has to reach the console. A file server that only hands out boot files cannot accept that report, and the machine will not move on to Talos.

!!! tip

    Stop after commission when you want to inspect the wipe before Talos is served. Stop after Talos when you want maintenance mode and you do not want the deploy job to continue into inventory and OpenStack.

## Install

The console has its own releases. The published release for this page is [v2026.10.02](https://github.com/PIndustries/genestack-console/releases/tag/v2026.10.02){:target="_blank"}. The Linux asset is `genestack-console-linux-amd64`. [`version.json`](https://github.com/PIndustries/genestack-console/releases/download/v2026.10.02/version.json){:target="_blank"} on that release points at the download URL.

On a Linux deploy host the console install prefix is `/opt/genestack-console`. That is next to `/opt/genestack`, not inside it. The UI binds `127.0.0.1:8080` until you change `server.host` in the console config. The first admin password is written to `/opt/genestack-console/ADMIN_CREDENTIALS.txt` with mode `0600`.

The console repository documents a one-line installer for Linux, WSL, and a Mac lab. That installer downloads from the console release channel. When you need the binary built for `v2026.10.02`, use the GitHub Release asset named above. The full host matrix, systemd layout, and laptop lab are in the console install guide.

``` shell
curl -fsSL https://get.genestack.dev/console.sh | bash
```

Treat the console data directory and `config.yaml` as credentials. The database holds users, sessions, and encrypted BMC secrets. A backup of the database without the matching config cannot decrypt those secrets. The console repository documents the backup command.

## my.genestack.dev

`https://my.genestack.dev` is the account portal for a console you run. It is how the Apple apps reach that console, and it is where an account holder manages the account and asks us for support. The environment, the jobs, the BMC secrets, and the cluster stay on the console process on your deploy host.

The portal does not run a copy of the console. There is nothing to operate there except the account and the link to a console you already installed. Sign-in from a Mac, iPhone, iPad, or Apple Watch goes to the portal, and the portal forwards that session to your console. On the console itself, operators can still sign in with a local account, an API key, or their own identity provider, with no portal in the path.

The issuer, redirect, and cookie settings are in [Connect a console to my.genestack.dev](https://github.com/PIndustries/genestack-console/blob/main/docs/hosted-mode.md){:target="_blank"}.

## Where the rest of the manual lives

Source and releases are in [PIndustries/genestack-console](https://github.com/PIndustries/genestack-console){:target="_blank"}. Use this page to see how the console fits Genestack. Use the console repository for the procedure that ships with a console tag.

| You need | Read |
| --- | --- |
| Install, systemd, Mac and WSL labs | [Install](https://github.com/PIndustries/genestack-console/blob/v2026.10.02/docs/install.md){:target="_blank"} |
| A local all-in-one lab | [Install AIO](https://github.com/PIndustries/genestack-console/blob/v2026.10.02/docs/install-aio.md){:target="_blank"} |
| Jobs, agents, auth, and the service layers | [Architecture](https://github.com/PIndustries/genestack-console/blob/v2026.10.02/docs/architecture.md){:target="_blank"} |
| Portal account and Apple sign-in | [Connect a console to my.genestack.dev](https://github.com/PIndustries/genestack-console/blob/main/docs/hosted-mode.md){:target="_blank"} |
| HTTP API | [API reference](https://github.com/PIndustries/genestack-console/blob/v2026.10.02/API_REFERENCE.md){:target="_blank"}, and `/swagger` on a running console |
| How a release is cut | [Releasing](https://github.com/PIndustries/genestack-console/blob/v2026.10.02/docs/releasing.md){:target="_blank"} |

!!! note

    [docs.rackspacecloud.com](https://docs.rackspacecloud.com){:target="_blank"} builds from the `main` branch of this repository. Genestack `main` can move ahead of a Genestack release tag, and the console moves on its own tags. When this page and a console release disagree, follow the console repository at that release tag.
