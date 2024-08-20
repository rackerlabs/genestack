# Creating the Compute Kit Secrets

Part of running Nova is also running placement. Setup all credentials now so we can use them across the nova and placement services.

!!! note "Information about the secretes used"

    Manual secret generation is only required if you haven't run the `create-secrets.sh` script located in `/opt/genestack/bin`.

    ??? example "Example secret generation"

        ### Shared

        ``` shell
        kubectl --namespace openstack \
                create secret generic metadata-shared-secret \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        ```

        ### Placement

        ``` shell
        kubectl --namespace openstack \
                create secret generic placement-db-password \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        kubectl --namespace openstack \
                create secret generic placement-admin \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        ```

        ### Nova

        ``` shell
        kubectl --namespace openstack \
                create secret generic nova-db-password \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        kubectl --namespace openstack \
                create secret generic nova-admin \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        kubectl --namespace openstack \
                create secret generic nova-rabbitmq-password \
                --type Opaque \
                --from-literal=username="nova" \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-64};echo;)"
        ssh-keygen -qt ed25519 -N '' -C "nova_ssh" -f nova_ssh_key && \
        kubectl --namespace openstack \
                create secret generic nova-ssh-keypair \
                --type Opaque \
                --from-literal=public_key="$(cat nova_ssh_key.pub)" \
                --from-literal=private_key="$(cat nova_ssh_key)"
        rm nova_ssh_key nova_ssh_key.pub
        ```

        ### Ironic (NOT IMPLEMENTED YET)

        ``` shell
        kubectl --namespace openstack \
                create secret generic ironic-admin \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        ```

        ### Designate (NOT IMPLEMENTED YET)

        ``` shell
        kubectl --namespace openstack \
                create secret generic designate-admin \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        ```

        ### Neutron

        ``` shell
        kubectl --namespace openstack \
                create secret generic neutron-rabbitmq-password \
                --type Opaque \
                --from-literal=username="neutron" \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-64};echo;)"
        kubectl --namespace openstack \
                create secret generic neutron-db-password \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        kubectl --namespace openstack \
                create secret generic neutron-admin \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        ```
