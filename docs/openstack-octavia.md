# Deploy Octavia

OpenStack Octavia is the load balancing service within the OpenStack ecosystem, providing scalable and automated load
balancing for cloud applications. Octavia is designed to ensure high availability and reliability by distributing
incoming network traffic across multiple instances of an application, preventing any single instance from becoming a
bottleneck or point of failure. It supports various load balancing algorithms, health monitoring, and SSL termination,
making it a versatile tool for managing traffic within cloud environments. In this document, we will explore the
deployment of OpenStack Octavia using Genestack. By leveraging Genestack, the deployment of Octavia is streamlined,
ensuring that load balancing is seamlessly incorporated into both private and public cloud environments, enhancing
the performance and resilience of cloud applications.

## Create secrets

!!! note "Information about the secretes used"

    Manual secret generation is only required if you haven't run the `create-secrets.sh` script located in `/opt/genestack/bin`.

    ??? example "Example secret generation"

        ``` shell
        kubectl --namespace openstack \
                create secret generic octavia-rabbitmq-password \
                --type Opaque \
                --from-literal=username="octavia" \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-64};echo;)"
        kubectl --namespace openstack \
                create secret generic octavia-db-password \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        kubectl --namespace openstack \
                create secret generic octavia-admin \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        kubectl --namespace openstack \
                create secret generic octavia-certificates \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        ```

## Prerequisite

Before you can deploy octavia, it requires a few things to be setup ahead of time:

* Quota check/update
* Certificate creation
* Security group configuration
* Amphora management network
* Port creation for health manager pods
* Amphora image creation
* and more

In order to automate these tasks, we have provided an ansible role and a playbook. The playbook, `octavia-preconf-main.yaml`,
is located in the ansible/playbook directory. You will need to update the variables in the playbook to match your deployment.

Make sure to udpate the `octavia-preconf-main.yaml` with the correct region, auth url, and password.

!!! tip

    The playbook requires a few pip packages to run properly. While the dependencies for this playbook should be installed by
    default, the playbook runtime can be isolated in a virtualenv if needed.

    ??? example "Create a virtualenv for running the Octavia pre-deployment playbook"

        ``` shell
        apt-get install python3-venv python3-pip
        mkdir -p ~/.venvs
        python3 -m venv --system-site-packages ~/.venvs/octavia_preconf
        source .venvs/octavia_preconf/bin/activate
        pip install --upgrade pip
        pip install "ansible>=2.9" "openstacksdk>=1.0.0" "python-openstackclient==6.2.0" kubernetes
        ```

### Review the role values

The default values are in `/opt/genestack/ansible/playbooks/roles/octavia_preconf/defaults/main.yml`

Review the settings and adjust as necessary. Depending on the size of your cluster, you may want to adjust the
`lb_mgmt_subnet` settings or block icmp and ssh access to the amphora vms.

### Run the playbook

Change to the playbook directory.

``` shell
cd /opt/genestack/ansible/playbooks
```

=== "Dynamic values"

    Running the playbook can be fully dynamic by using the following command:

    !!! example "Run the playbook with dynamic values"

        ``` shell
        ansible-playbook /opt/genestack/ansible/playbooks/octavia-preconf-main.yaml \
                        -e octavia_os_password=$(kubectl get secrets keystone-admin -n openstack -o jsonpath='{.data.password}' | base64 -d) \
                        -e octavia_os_region_name=$(openstack --os-cloud=default endpoint list --service keystone --interface public -c Region -f value) \
                        -e octavia_os_auth_url=$(openstack --os-cloud=default endpoint list --service keystone --interface public -c URL -f value) \
                        -e octavia_helm_file=/tmp/octavia_amphora_provider.yaml
        ```

=== "Static values skipping tags for post deploy updates"

    You can get the Keystone url and region with the following command.

    ``` shell
    openstack --os-cloud=default endpoint list --service keystone --interface public -c Region -c URL -f value
    ```

    You can get the admin password by using kubectl.

    ``` shell
    kubectl get secrets keystone-admin -n openstack -o jsonpath='{.data.password}' | base64 -d
    ```

    !!! example "Run the playbook with optional skip-tags values"

        ``` shell
        ansible-playbook /opt/genestack/ansible/playbooks/octavia-preconf-main.yaml \
                        -e octavia_os_password=$PASSWORD \
                        -e octavia_os_region_name=$REGION_NAME \
                        -e octavia_os_auth_url=$AUTH_URL \
                        -e octavia_helm_file=/tmp/octavia_amphora_provider.yaml
        ```

=== "Skipping tags for pre deploy setup"

    If you have already run the pre-deployment steps and need to re-generate the helm values file, you can skip the
    pre-deployment steps by using the `--skip-tags "pre_deploy"` option.

    !!! example "Run the playbook with optional skip-tags values"

        ``` shell
        ansible-playbook /opt/genestack/ansible/playbooks/octavia-preconf-main.yaml \
                        --skip-tags "pre_deploy"
        ```

Once everything is complete, a new file will be created in your TMP directory called `/tmp/octavia_amphora_provider.yaml`, this file
contains the necessary information to deploy Octavia via helm. Move this file into the `/etc/genestack/helm-configs/octavia`
directory to have it automatically included when running the Octavia deployment script.

``` shell
mv /tmp/octavia_amphora_provider.yaml /etc/genestack/helm-configs/octavia/
```

## Run the Helm deployment

??? example "Run the Octavia deployment Script `/opt/genestack/bin/install-octavia.sh`"

    ``` shell
    --8<-- "bin/install-octavia.sh"
    ```

!!! tip

    You may need to provide custom values to configure your openstack services, for a simple single region or lab deployment
    you can supply an additional overrides flag using the example found at `base-helm-configs/aio-example-openstack-overrides.yaml`.
    In other cases such as a multi-region deployment you may want to view the [Multi-Region Support](multi-region-support.md)
    guide to for a workflow solution.

## Demo

[![asciicast](https://asciinema.org/a/629814.svg)](https://asciinema.org/a/629814)
