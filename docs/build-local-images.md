# Building Custom Images

## Octavia OVN with customer providers

By default Octavia will run with Amphora, however, because we've OVN available to our environment we can also configure the OVN provider for use within the cluster. While the genestack defaults will include a container image that meets our needs, the following snippet will walk you through the manual build process making use of the internal kubernetes registry.

``` shell
# Pre-made container files for build purposes can be found within the repo.
cd /opt/genestack/Containerfiles

# Install buildah.
apt update
apt -y install buildah

# Build the ovn integration into the ovn release image. Note the version argument.
# this option is variable and should be adjusted for your specific needs.
buildah build -f OctaviaOVN-Containerfile --build-arg VERSION=master-ubuntu_jammy
# List the local images to get the IP of the new image.
buildah images

REPOSITORY               TAG                   IMAGE ID         CREATED          SIZE
<none>                   <none>                THISISTHENEWIMG  11 minutes ago   388 MB
docker.io/loci/octavia   master-ubuntu_jammy   THISISTHEBASE    3 weeks ago      323 MB

# Push the new image to our internal registry.
buildah push --tls-verify=false THISISTHENEWIMG docker://registry.kube-system/octavia:ubuntu_jammy-ovn

# You can validate that the image is present.
curl -k https://registry.kube-system/v2/_catalog

# Create an override file.
cat > /opt/octavia-ovn-helm-overrides.yaml <<EOF
images:
  tags:
    octavia_db_sync: registry.kube-system/octavia:ubuntu_jammy-ovn
    octavia_api: registry.kube-system/octavia:ubuntu_jammy-ovn
    octavia_worker: registry.kube-system/octavia:ubuntu_jammy-ovn
    octavia_housekeeping: registry.kube-system/octavia:ubuntu_jammy-ovn
    octavia_health_manager: registry.kube-system/octavia:ubuntu_jammy-ovn
EOF

# Retrieve the registry CA
kubectl --namespace kube-system get secret registry-kube-system-cert -o jsonpath='{.data.ca\.crt}' | base64 -d > /opt/registry.ca
```

!!! note

    the above commands make the assumption that you're running a docker registry within the kube-system namespace and are running the provided genestack ingress definition to support that environment. If you have a different registry you will need to adjust the commands to fit your environment.

Once the above commands have been executed, the file `/opt/octavia-ovn-helm-overrides.yaml` will be present and can be included in our helm command when we deploy Octavia.

!!! tip

    If you're using the local registry with a self-signed certificate, you will need to include the CA `/opt/registry.ca` in all of your potential worker nodes so that the container image is able to be pulled.
