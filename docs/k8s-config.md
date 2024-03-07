Once the environment is online, proceed to login to the environment and begin the deployment normally. You'll find the launch node has everything needed, in the places they belong, to get the environment online.

## Install `kubectl`

Install the `kubectl` tool.

``` shell
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo mv kubectl /usr/local/bin/
sudo chmod +x /usr/local/bin/kubectl
```

## Retrieve the kube config

Retrieve the kube config from our first controller.

!!! tip

    In the following example, X.X.X.X is expected to be the first controller.

!!! note

    In the following example, ubuntu is the assumed user.

``` shell
mkdir -p ~/.kube
rsync -e "ssh -F ${HOME}/.ssh/openstack-flex-keypair.config" \
      --rsync-path="sudo rsync" \
      -avz ubuntu@X.X.X.X:/root/.kube/config "${HOME}/.kube/config"
```

Edit the kube config to point at the first controller.

``` shell
sed -i 's@server.*@server: https://X.X.X.X:6443@g' "${HOME}/.kube/config"
```
