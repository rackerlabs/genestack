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

The console is published on its own: [PIndustries/genestack-console](https://github.com/PIndustries/genestack-console){:target="_blank"}. This page is the chapter in the Genestack manual. The pages after it walk through the program. Install details for a Mac or Windows, and how a release is cut, stay in that repository.

## Install the console

On the deploy host:

``` shell
curl -fsSL https://get.genestack.dev/console.sh | bash
```

That address redirects to the current installer attached to a GitHub Release. The script installs the program under `/opt/genestack-console` and starts a web page at `127.0.0.1:8080`. The page listens only on the deploy host until you change `server.host`.

Run the same install command again and it moves the binary to the latest release. `genestack-console update` does only that replace. Neither one changes `config.yaml`, the database, or `/opt/genestack`. A published tag stays available: `curl -fsSL https://get.genestack.dev/console.sh | bash -s -- --version 2026.10.04.3`.

A production deploy host runs that published binary. A git checkout is for changing the console and testing that change. Running the checkout in production is possible. The install we support is the binary.

From a laptop, forward that port:

``` shell
ssh -L 8080:127.0.0.1:8080 <deploy-host>
```

Open `http://127.0.0.1:8080/ui`. The first screen is Guided setup. The first admin password is written to `/opt/genestack-console/ADMIN_CREDENTIALS.txt`. The file mode is `0600`.

That command always installs the latest release. The Linux file is `genestack-console-linux-amd64`. [`version.json`](https://github.com/PIndustries/genestack-console/releases/latest/download/version.json){:target="_blank"} on that release names the file. Released files are listed at [genestack.dev/releases](https://genestack.dev/releases){:target="_blank"}.

Back up two things together: `/opt/genestack-console/config.yaml`, and the console database. The database holds the users and the sessions. Passwords stored in it are encrypted with a key from `config.yaml`. A copy of the database without that file cannot be decrypted.

## Boot the console as an appliance

The command above puts the program on a Linux server you already have. The latest release ships a boot image for a machine that does not have an operating system yet. The image is Ubuntu 26.04 with the console already on it. SSH is installed and does not start. The page listens on port 8080 on the machine's addresses, so you open `http://<address>:8080/ui` without an SSH forward.

Two files are on the [latest release](https://github.com/PIndustries/genestack-console/releases/latest){:target="_blank"}:

- `genestack-console-appliance-<version>-amd64.qcow2.xz` is a virtual machine disk with the console already installed. Decompress it and boot it.
- `genestack-console-appliance-<version>-amd64.iso` is a CD. Boot it and type the disk to install onto. That disk is wiped. The installed system is the same appliance as the virtual machine disk.

The first boot writes the admin password on the machine console, in `/opt/genestack-console/ADMIN_CREDENTIALS.txt`. The resize, the OpenStack import, and the install prompt are in [The appliance](https://github.com/PIndustries/genestack-console/blob/main/docs/appliance.md){:target="_blank"}.

This CD is the console itself. A server ISO you boot yourself is a different file. That one installs a machine into the cloud.

## Where the files go

Clone this repository first. [Getting the code](genestack-getting-started.md) is that step. On the deploy host the checkout lives at `/opt/genestack`.

`bootstrap.sh`, in that checkout, creates `/etc/genestack`. That directory is the inventory and the settings the install reads. One file it writes is `/etc/genestack/provider`, which records which Kubernetes installer you are using. Kubespray is the default. It installs Kubernetes onto machines that already have an operating system. Talos is the other choice. Talos is an operating system that boots a machine straight into Kubernetes. The Talos bare-metal steps on this page follow the same order as [Talos Linux](k8s-talos.md): wipe the disks, boot Talos, then send the machine config. Ubuntu is a different next boot. It installs one machine and stops. It is not a value in the provider file.

| Path | What it is |
| --- | --- |
| `/opt/genestack` | This repository, on the deploy host. The console runs the scripts from here. |
| `/etc/genestack` | Inventory and settings. `bootstrap.sh` creates the directory. You still edit the files the way the rest of this manual describes. |
| `/opt/genestack-console` | The console program. It is installed beside this checkout. It is not a folder inside it. |
| `127.0.0.1:8080` | The console web page, on the deploy host. |

The console source is [PIndustries/genestack-console](https://github.com/PIndustries/genestack-console){:target="_blank"}. It is not pinned in this repository. The install command above is how you get the program.

## What you do in the console

An environment is one cloud: a lab, one rack, or one region. A second cloud is a second environment. The servers in one environment stay in that environment. A tenant is the group of people allowed to use that cloud. Jobs and passwords for the cloud stay inside the environment.

Point the environment at `/opt/genestack` and at the `/etc/genestack` directory `bootstrap.sh` already created. Saving settings in the console does not change those directories by itself. A job copies the saved settings onto the deploy host, then runs the install scripts from this tree. The log of that job stays on the environment.

The console database on the deploy host holds the passwords, the kubeconfig, and the management-port passwords. A job writes `kubesecrets.yaml` so the install scripts can read it, and removes that file when the job finishes, including when the job fails or is cancelled. A kubeconfig the job created is stored in that database and then removed from the deploy host. A kubeconfig path that was already on the host stays. [How a job runs](genestack-console-runtime.md) is the longer account of that cleanup.

When the install has finished, the same environment is where you look at Kubernetes, act on namespaces, nodes, and pods, run the OpenStack service steps, and download two credential files. The kubeconfig is how you talk to Kubernetes. The talosconfig is how you talk to Talos. Both are saved in that environment's vault. Download grabs the vault copy. An admin can view, edit, and delete a record in that vault. Regenerate asks the cluster for a new client certificate, valid for one year, and replaces the vault copy. Skyline is the OpenStack web page for people using the cloud day to day. Open Horizon, on the OpenStack tab, opens the Horizon dashboard in the console window. New tab opens that same page. The login uses the cloud admin account. The console is the page for the people who build the cloud.

People who sign in have one of three roles: viewer, operator, or admin. An API key in `config.yaml` is the emergency login, for when the user accounts cannot be used.

## How a server gets an operating system

Where the deploy host is L2 with the servers, the console answers DHCP and serves the boot file on that network. DHCP is how a machine asks for an IP address. The boot file is the small program the network card downloads when the server is told to start from the network instead of from its disk. Both services run inside the console. This is how the console installs an operating system. Talos and Ubuntu are the two it installs from the network. You do not install a separate DHCP server, or another program, to boot the machines.

A management port is part of that install. You can start without one. A lab is the console plus the machines you have: a Mac with one local virtual machine, one Ubuntu machine, one dedicated server, or three machines in one environment. The cloud machine can be physical or a virtual machine on the hypervisor you already run. [Your first cluster](https://github.com/PIndustries/genestack-console/blob/main/docs/first-cluster.md){:target="_blank"} has those starts, the Talos ISO, the guest size, and the switch that makes the environment apply. If Talos is already running from an ISO, including a virtual machine, add the host by name and address and choose Talos is already installed. The console applies the config to every saved address. A machine that already has Talos installed is not rebooted until you confirm that machine by name. Confirming replaces the running install. A management port can do that reboot after the confirm. If this console cannot reboot it, the job names the one step left and waits until the installer is up. If Ubuntu is already installed on a group of servers, add those hosts and choose Already have an OS. That records them for Kubespray. It does not reboot them. [Your first cluster](https://github.com/PIndustries/genestack-console/blob/main/docs/first-cluster.md){:target="_blank"} is the walkthrough. The management port is still how you power a machine, network-boot it, and open its console when the hardware has one.

Each server has two addresses you type in on the network-boot path.

- The management port. Vendors call it the BMC, iLO, or iDRAC. It is a small controller inside the server that stays on when the main computer is off. The console uses it to power the server, and to ask the server to boot from the network one time.
- The port on the L2 network. The console, or the agent at a remote site, matches that port by its MAC address. A MAC address is the hardware address of the network card.

Every server has its own next boot.

- **Disk** is the default. A server you have never asked the console to install boots from its own disk.
- **Commission** is a small system that runs from memory. It wipes the starts of the fixed disks and sends one report back to the console.
- **Talos** is offered to that server only after the report has been accepted. The Talos machine config is sent after the wipe. It is not placed on the boot command line.
- **Ubuntu** installs that one machine. It uses the whole disk. The login user is `ubuntu` and the key is the environment SSH public key the console already keeps. The seed is `data/pxe/ubuntu/<hostname>/`. Place the kernel and initrd at `data/pxe/ubuntu/vmlinuz` and `data/pxe/ubuntu/initrd`. The job does not download them. This boot does not install OpenStack or Kubernetes, and it does not require the commission wipe. The node name has to be a hostname, and the node needs a PXE MAC.

A server the console has not selected downloads a short script and then returns to its own disk. It is left alone.

For a server you did select:

1. The console writes the wipe program for that MAC address and asks the management port to network-boot the server once.
2. The wipe program clears the disks and posts one report. Sending the same report again does not wipe the disks again.
3. The console switches that server to Talos and network-boots it once.
4. Talos comes up in maintenance. Maintenance means Talos is running and waiting for its configuration. The job then continues with the [Talos Linux](k8s-talos.md) steps in this manual.

Those four steps are the Talos path. Install Ubuntu is a separate next boot. It writes that machine's seed and can power the machine from the network. It does not run the wipe, and it does not continue into OpenStack. A Machines row queues that boot and waits until the machine answers.

An ISO image cannot be the first boot of a reinstall. An ISO does not wipe the disks, so the console rejects that choice on this path. An ISO you boot yourself, on a guest that has no management port, is a different start. The console does not insert that ISO. You boot it, then point the console at the machine.

Where the deploy host cannot be L2 with the servers, the console agent does this job. Install it on a computer that is L2 with those servers. DHCP and the boot files for that site run on the agent. The agent connects out to the console, and you still start the job from the console. The agent install is in the console install guide linked below.

!!! warning

    The wipe report has to reach the console. If some other machine hands out the boot file, and the report never arrives, the server stays on the wipe image. The console is what accepts the report and switches that server over to Talos.

!!! tip

    Stop the job after the wipe if you want to inspect the disks before Talos is served. Stop after Talos if you want the server left in maintenance, and you do not want the job to continue into inventory and OpenStack.

## my.genestack.dev

`https://my.genestack.dev` is the account page for a console you already installed. On that page you manage the account, connect the Mac, iPhone, iPad, and Apple Watch apps to the console, and ask for support. The apps sign in on that page. The page then opens your console.

The environment, the job log, and the management-port passwords stay in the console database on the deploy host, in `/opt/genestack-console`. People on the deploy host can sign in with a local user, an API key, or their company's login, and never open the account page.

How the sign-in is configured is written in [Connect a console to my.genestack.dev](https://github.com/PIndustries/genestack-console/blob/main/docs/hosted-mode.md){:target="_blank"}.

## What the code is doing

The installed program is one Linux binary and two processes. The first serves this page, the API, and, when the deploy host is L2 with the servers, DHCP and the boot file. The second is the worker. A click records a job. The worker runs it, so a long install is not stuck inside the browser request.

The source is the Python package `app` in the console repository.

| Path | What it is |
| --- | --- |
| `app/main.py` | Starts the API process and attaches every route. |
| `app/routers/` | One file per area of the API. A route checks who you are, then reads or queues a job. |
| `app/services/` | The work those routes and jobs call: the settings document, the pipeline, DHCP, the management port. |
| `app/modules/` | The jobs. One folder per area. One Python file per operation. The folder's `__init__.py` lists those files and does not call them. |
| `app/services/job_runner.py` | Prepares the environment, then calls the one function that matches the job. |
| `app/worker/runner.py` | Claims queued jobs. Two workers cannot take the same row. |
| `app/models.py`, `app/db.py` | The tables, and the code that opens them. There is no separate migration tool. |
| `app/static/`, `app/templates/ui.html` | The web page. The shell is the HTML file. Each screen is a JavaScript file. |
| `config.yaml` | Bind address, secret key, API keys, the database, and any extra module folders. |
| `agent/` | The program you install at a site this machine cannot reach at L2. It connects out. |

The next pages walk through that split.

| Page | What it explains |
| --- | --- |
| [The program](genestack-console-program.md) | The two processes, the database, who can sign in, the collector, and the agent. |
| [How a job runs](genestack-console-runtime.md) | From the click, to the worker, to `/opt/genestack`, including the settings document and DHCP. |
| [Jobs](genestack-console-jobs.md) | Every operation that ships, the pipeline stages, and how to add one. |
| [The HTTP API](genestack-console-api.md) | How a call is authenticated, and which file serves which route. |
| [The web page](genestack-console-ui.md) | The sidebar, one environment, and what each screen file draws. |

## Adding an operation

An operation is one job the console knows how to run: power a server, push config, deploy. Each one is a Python file. The files for one area sit in a folder. The folder's `__init__.py` is the class that lists those files, in order. It does not call them.

The built-in folders live under `app/modules/`. Bare metal is `app/modules/baremetal/`. To add your own, make a folder with the same shape and put its path in `modules.paths` in `config.yaml`. The console loads it on startup. The full list, the pipeline, and the steps are on [Jobs](genestack-console-jobs.md). The same layout, with a worked example, is [Modules](https://github.com/PIndustries/genestack-console/blob/main/docs/modules.md){:target="_blank"}.

## The rest of the manual

The first rows are the rest of this chapter. The links after them open the console repository. Getting Started installs the latest release.

| You need | Read |
| --- | --- |
| The console is installed and you want a cluster | [Your first cluster](https://github.com/PIndustries/genestack-console/blob/main/docs/first-cluster.md){:target="_blank"} |
| The two processes and the database | [The program](genestack-console-program.md) |
| How a click becomes a command | [How a job runs](genestack-console-runtime.md) |
| Every operation, and how to add one | [Jobs](genestack-console-jobs.md) |
| The HTTP routes | [The HTTP API](genestack-console-api.md) |
| The screens | [The web page](genestack-console-ui.md) |
| Install on Linux, a Mac, or Windows | [Install](https://github.com/PIndustries/genestack-console/blob/main/docs/install.md){:target="_blank"} |
| Boot the console as an appliance | [The appliance](https://github.com/PIndustries/genestack-console/blob/main/docs/appliance.md){:target="_blank"} |
| A lab with one local virtual machine | [Install AIO](https://github.com/PIndustries/genestack-console/blob/main/docs/install-aio.md){:target="_blank"} |
| The longer design notes | [Architecture](https://github.com/PIndustries/genestack-console/blob/main/docs/architecture.md){:target="_blank"} |
| The account page and the Apple apps | [Connect a console to my.genestack.dev](https://github.com/PIndustries/genestack-console/blob/main/docs/hosted-mode.md){:target="_blank"} |
| Path-by-path HTTP reference | [API reference](https://github.com/PIndustries/genestack-console/blob/main/API_REFERENCE.md){:target="_blank"}, and `/swagger` on a running console |
| How a release is cut | [Releasing](https://github.com/PIndustries/genestack-console/blob/main/docs/releasing.md){:target="_blank"} |

!!! note

    This site is built from the `main` branch of Genestack. The console program is released on its own. The install command on this page follows the latest release. If a step on this page and the program you installed disagree, follow the latest console release.
