# Install Kubernetes Tools/Plugins

Once the environment is online, proceed to login to the environment and begin the deployment normally. You'll find the launch node has everything needed, in the places they belong, to get the environment online.

## Install `kubectl`

Install the `kubectl` tool.

``` shell
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```

### Install the `convert` plugin

The convert plugin can be used to assist with upgrades.

``` shell
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl-convert"
sudo install -o root -g root -m 0755 kubectl-convert /usr/local/bin/kubectl-convert
```

### Install the `ko` plugin

Facilitates daily operations and maintenance, allowing administrators to perform daily operations like: Check OVN database information and status, OVN database backup and restore, OVS related information, tcpdump specific containers, specific link logical topology, network problem diagnosis and performance optimization.

``` shell
curl -LO https://raw.githubusercontent.com/kubeovn/kube-ovn/release-1.12/dist/images/kubectl-ko
sudo install -o root -g root -m 0755 kubectl-ko /usr/local/bin/kubectl-ko
```
