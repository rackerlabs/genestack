# Genestack Console

Genestack is this repository. It is the scripts, Ansible playbooks, and charts that install OpenStack on Kubernetes.

Genestack Console is a different program. Install it on its own Linux server. Clone this repository onto that same server, then open the console in a browser. From that page you:

- save the settings for one cloud
- turn the physical servers on and off
- give a server an IP address and a boot file while you install an operating system on it
- run the scripts in this repository and read the log

That server is the deploy host. The deploy host is the machine that performs the install. The cluster is the Kubernetes and OpenStack cloud the scripts in this repository build. The deploy host never joins the cluster. It stays just outside the cloud, so you reach the servers from this machine and not through the cluster. If the cluster stops answering, you can still power the servers and run the install from here. The console, the saved settings, the job log, and the passwords you save there stay on that machine.

We recommend the deploy host be L2 with the servers you are installing. L2 means they are on one local network. On that network the console can give a server an IP address and a boot file itself. The section below says how that boot works.

When the deploy host cannot be L2 with a site, install the console agent on a computer that is. The agent gives out the addresses and the boot files at that site, and it connects out to the console. You still run the job from the console. One console often looks after several sites this way, such as more than one datacenter in the same private cloud.

The console is published on its own: [PIndustries/genestack-console](https://github.com/PIndustries/genestack-console){:target="_blank"}. This page is the chapter in the Genestack manual. Install details, the HTTP API, and the release notes are in that repository.

## Install the console

On the deploy host:

``` shell
curl -fsSL https://get.genestack.dev/console.sh | bash
```

That address redirects to the current installer attached to a GitHub Release. The script installs the program under `/opt/genestack-console` and starts a web page at `127.0.0.1:8080`. The page listens only on the deploy host until you change `server.host`.

From a laptop, forward that port:

``` shell
ssh -L 8080:127.0.0.1:8080 <deploy-host>
```

Open `http://127.0.0.1:8080/ui`. The first screen is Guided setup. The first admin password is written to `/opt/genestack-console/ADMIN_CREDENTIALS.txt`. The file mode is `0600`.

The build described here is [v2026.10.03](https://github.com/PIndustries/genestack-console/releases/tag/v2026.10.03){:target="_blank"}. The Linux file on that release is `genestack-console-linux-amd64`. [`version.json`](https://github.com/PIndustries/genestack-console/releases/download/v2026.10.03/version.json){:target="_blank"} on the same release names that file. Use those assets when you need this exact version. The `curl` command above follows whatever the latest release is.

Back up two things together: `/opt/genestack-console/config.yaml`, and the console database. The database holds the users and the sessions. Passwords stored in it are encrypted with a key from `config.yaml`. A copy of the database without that file cannot be decrypted.

## Where the files go

Clone this repository first. [Getting the code](genestack-getting-started.md) is that step. On the deploy host the checkout lives at `/opt/genestack`.

`bootstrap.sh`, in that checkout, creates `/etc/genestack`. That directory is the inventory and the settings the install reads. One file it writes is `/etc/genestack/provider`, which records which Kubernetes installer you are using. Kubespray is the default. It installs Kubernetes onto machines that already have an operating system. Talos is the other choice. Talos is an operating system that boots a machine straight into Kubernetes. The bare-metal steps on this page follow the same order as [Talos Linux](k8s-talos.md): wipe the disks, boot Talos, then send the machine config.

| Path | What it is |
| --- | --- |
| `/opt/genestack` | This repository, on the deploy host. The console runs the scripts from here. |
| `/etc/genestack` | Inventory and settings. `bootstrap.sh` creates the directory. You still edit the files the way the rest of this manual describes. |
| `/opt/genestack-console` | The console program. It is installed beside this checkout. It is not a folder inside it. |
| `submodules/genestack-console` | The console source, pinned in this repository the same way Kubespray is pinned. A normal clone does not download it. |
| `127.0.0.1:8080` | The console web page, on the deploy host. |

The pin is [PIndustries/genestack-console](https://github.com/PIndustries/genestack-console){:target="_blank"} at release `v2026.10.03`. The submodule is marked `ignore = all`, so a normal clone skips it. Fetch the source when you want it next to this tree:

``` shell
git submodule update --init submodules/genestack-console
```

## What you do in the console

An environment is one cloud: a lab, one rack, or one region. A tenant is the group of people allowed to use that cloud. Jobs and passwords for the cloud stay inside the environment.

Point the environment at `/opt/genestack` and at the `/etc/genestack` directory `bootstrap.sh` already created. Saving settings in the console does not change those directories by itself. A job copies the saved settings onto the deploy host, then runs the install scripts from this tree. The log of that job stays on the environment.

When the install has finished, the same environment is where you look at Kubernetes, act on namespaces, nodes, and pods, run the OpenStack service steps, and download two credential files. The kubeconfig is how you talk to Kubernetes. The talosconfig is how you talk to Talos. Skyline is the OpenStack web page for people using the cloud day to day. The console is the page for the people who build the cloud.

People who sign in have one of three roles: viewer, operator, or admin. An API key in `config.yaml` is the emergency login, for when the user accounts cannot be used.

## How a server gets an operating system

Where the deploy host is L2 with the servers, the console answers DHCP and serves the boot file on that network. DHCP is how a machine asks for an IP address. The boot file is the small program the network card downloads when the server is told to start from the network instead of from its disk. Both services run inside the console. This is how a server gets Talos. Talos is installed from the network, and the console is the program that does it. You do not install a separate DHCP server, or another program, to boot the machines.

Each server has two addresses you type in.

- The management port. Vendors call it the BMC, iLO, or iDRAC. It is a small controller inside the server that stays on when the main computer is off. The console uses it to power the server, and to ask the server to boot from the network one time.
- The port on the L2 network. The console, or the agent at a remote site, matches that port by its MAC address. A MAC address is the hardware address of the network card.

Every server has its own next boot.

- **Disk** is the default. A server you have never asked the console to install boots from its own disk.
- **Commission** is a small system that runs from memory. It wipes the starts of the fixed disks and sends one report back to the console.
- **Talos** is offered to that server only after the report has been accepted. The Talos machine config is sent after the wipe. It is not placed on the boot command line.

A server the console has not selected downloads a short script and then returns to its own disk. It is left alone.

For a server you did select:

1. The console writes the wipe program for that MAC address and asks the management port to network-boot the server once.
2. The wipe program clears the disks and posts one report. Sending the same report again does not wipe the disks again.
3. The console switches that server to Talos and network-boots it once.
4. Talos comes up in maintenance. Maintenance means Talos is running and waiting for its configuration. The job then continues with the [Talos Linux](k8s-talos.md) steps in this manual.

An ISO image cannot be the first boot of a reinstall. An ISO does not wipe the disks, so the console rejects that choice on this path.

Where the deploy host cannot be L2 with the servers, the console agent does this job. Install it on a computer that is L2 with those servers. DHCP and the boot files for that site run on the agent. The agent connects out to the console, and you still start the job from the console. The agent install is in the console install guide linked below.

!!! warning

    The wipe report has to reach the console. If some other machine hands out the boot file, and the report never arrives, the server stays on the wipe image. The console is what accepts the report and switches that server over to Talos.

!!! tip

    Stop the job after the wipe if you want to inspect the disks before Talos is served. Stop after Talos if you want the server left in maintenance, and you do not want the job to continue into inventory and OpenStack.

## my.genestack.dev

`https://my.genestack.dev` is the account page for a console you already installed. On that page you manage the account, connect the Mac, iPhone, iPad, and Apple Watch apps to the console, and ask for support. The apps sign in on that page. The page then opens your console.

The environment, the job log, and the management-port passwords stay on the deploy host, in `/opt/genestack-console`. People on the deploy host can sign in with a local user, an API key, or their company's login, and never open the account page.

How the sign-in is configured is written in [Connect a console to my.genestack.dev](https://github.com/PIndustries/genestack-console/blob/main/docs/hosted-mode.md){:target="_blank"}.

## Adding an operation

An operation is one job the console knows how to run: power a server, push config, deploy. Each one is a Python file. The files for one area sit in a folder. The folder's `__init__.py` is the class that lists those files, in order.

The built-in folders live in the console repository under `app/modules/`. Bare metal is `app/modules/baremetal/`. To add your own, make a folder with the same shape and put its path in `modules.paths` in `config.yaml`. The console loads it on startup. The layout and a worked example are in the console manual, [Modules](https://github.com/PIndustries/genestack-console/blob/main/docs/modules.md).

## The rest of the manual

The links below open the console repository. The binary named on this page is `v2026.10.03`. The manual can be ahead of that tag.

| You need | Read |
| --- | --- |
| Install on Linux, a Mac, or Windows | [Install](https://github.com/PIndustries/genestack-console/blob/main/docs/install.md){:target="_blank"} |
| A lab with one local virtual machine | [Install AIO](https://github.com/PIndustries/genestack-console/blob/main/docs/install-aio.md){:target="_blank"} |
| How the program is put together | [Architecture](https://github.com/PIndustries/genestack-console/blob/main/docs/architecture.md){:target="_blank"} |
| The account page and the Apple apps | [Connect a console to my.genestack.dev](https://github.com/PIndustries/genestack-console/blob/main/docs/hosted-mode.md){:target="_blank"} |
| HTTP API | [API reference](https://github.com/PIndustries/genestack-console/blob/v2026.10.03/API_REFERENCE.md){:target="_blank"}, and `/swagger` on a running console |
| How a release is cut | [Releasing](https://github.com/PIndustries/genestack-console/blob/main/docs/releasing.md){:target="_blank"} |

!!! note

    This site is built from the `main` branch of Genestack. The console program is released on its own tags. If a step on this page and the `v2026.10.03` binary disagree, follow the console repository at that tag.
