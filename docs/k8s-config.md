# Retrieve the kube config

Create the directory where the kube config will be stored.

``` shell
mkdir -p ~/.kube
```

Retrieve the kube config from our first controller.

!!! note

    In the following example, X.X.X.X is expected to be the first controller and the user is assumed to be Ubuntu.

``` shell
rsync -e "ssh -F ${HOME}/.ssh/openstack-keypair.config" \
      --rsync-path="sudo rsync" \
      -avz ubuntu@X.X.X.X:/root/.kube/config "${HOME}/.kube/config"
```

Edit the kube config to point at the first controller.

``` shell
sed -i 's@server.*@server: https://X.X.X.X:6443@g' "${HOME}/.kube/config"
```

Once you have the kube config and it is pointed at your kubernetes API nodes,
you can use `kubectl` to interact with the Kubernetes cluster.
