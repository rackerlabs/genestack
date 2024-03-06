# Building the cloud

From this point forward we're building our OpenStack cloud. The following commands will leverage `helm` as the package manager and `kustomize` as our configuration management backend.

## Deployment choices

When you're building the cloud, you have a couple of deployment choices, the most fundamental of which is `base` or `aio`.

* `base` creates a production-ready environment that ensures an HA system is deployed across the hardware available in your cloud.
* `aio` creates a minimal cloud environment which is suitable for test, which may have low resources.

The following examples all assume the use of a production environment, however, if you change `base` to `aio`, the deployment footprint will be changed for a given service.

## The DNA of our services

The DNA of the OpenStack services has been built to scale, and be managed in a pseudo light-outs environment. We're aiming to empower operators to do more, simply and easily. Here are the high-level talking points about the way we've structured our applications.

* All services make use of our core infrastructure which is all managed by operators.
* Backups, rollbacks, and package management all built into our applications delivery.
* Databases, users, and grants are all run against a MariaDB Galera cluster which is setup for OpenStack to use a single right, and read from many.
  * The primary node is part of application service discovery and will be automatically promoted / demoted within the cluster as needed.
* Queues, permissions, vhosts, and users are all backed by a RabbitMQ cluster with automatic failover. All of the queues deployed in the environment are done with Quorum queues, giving us a best of bread queing platform which gracefully recovers from faults while maintaining performance.
* Horizontal scaling groups have been applied to all of our services. This means we'll be able to auto scale API applications up and down based on the needs of the environment.

## Deploy Keystone

[![asciicast](https://asciinema.org/a/629802.svg)](https://asciinema.org/a/629802)

### Create secrets.

``` shell
kubectl --namespace openstack \
        create secret generic keystone-rabbitmq-password \
        --type Opaque \
        --from-literal=username="keystone" \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-64};echo;)"
kubectl --namespace openstack \
        create secret generic keystone-db-password \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
kubectl --namespace openstack \
        create secret generic keystone-admin \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
kubectl --namespace openstack \
        create secret generic keystone-credential-keys \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
```

### Run the package deployment

``` shell
cd /opt/genestack/submodules/openstack-helm

helm upgrade --install keystone ./keystone \
    --namespace=openstack \
    --wait \
    --timeout 120m \
    -f /opt/genestack/helm-configs/keystone/keystone-helm-overrides.yaml \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.keystone.password="$(kubectl --namespace openstack get secret keystone-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.admin.password="$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.keystone.password="$(kubectl --namespace openstack get secret keystone-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)" \
    --post-renderer /opt/genestack/kustomize/kustomize.sh \
    --post-renderer-args keystone/base
```

> In a production like environment you may need to include production specific files like the example variable file found in
  `helm-configs/prod-example-openstack-overrides.yaml`.

> NOTE: The image used here allows the system to run with RXT global authentication federation.
  The federated plugin can be seen here, https://github.com/cloudnull/keystone-rxt

Deploy the openstack admin client pod (optional)

``` shell
kubectl --namespace openstack apply -f /opt/genestack/manifests/utils/utils-openstack-client-admin.yaml
```

### Validate functionality

``` shell
kubectl --namespace openstack exec -ti openstack-admin-client -- openstack user list
```

## Deploy Glance

[![asciicast](https://asciinema.org/a/629806.svg)](https://asciinema.org/a/629806)

### Create secrets.

``` shell
kubectl --namespace openstack \
        create secret generic glance-rabbitmq-password \
        --type Opaque \
        --from-literal=username="glance" \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-64};echo;)"
kubectl --namespace openstack \
        create secret generic glance-db-password \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
kubectl --namespace openstack \
        create secret generic glance-admin \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
```

> Before running the Glance deployment you should configure the backend which is defined in the
  `helm-configs/glance/glance-helm-overrides.yaml` file. The default is a making the assumption we're running with Ceph deployed by
  Rook so the backend is configured to be cephfs with multi-attach functionality. While this works great, you should consider all of
  the available storage backends and make the right decision for your environment.

### Run the package deployment

``` shell
cd /opt/genestack/submodules/openstack-helm

helm upgrade --install glance ./glance \
    --namespace=openstack \
    --wait \
    --timeout 120m \
    -f /opt/genestack/helm-configs/glance/glance-helm-overrides.yaml \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.glance.password="$(kubectl --namespace openstack get secret glance-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.glance.password="$(kubectl --namespace openstack get secret glance-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.admin.password="$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.glance.password="$(kubectl --namespace openstack get secret glance-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)" \
    --post-renderer /opt/genestack/kustomize/kustomize.sh \
    --post-renderer-args glance/base
```

> In a production like environment you may need to include production specific files like the example variable file found in
  `helm-configs/prod-example-openstack-overrides.yaml`.

> Note that the defaults disable `storage_init` because we're using **pvc** as the image backend
  type. In production this should be changed to swift.

### Validate functionality

``` shell
kubectl --namespace openstack exec -ti openstack-admin-client -- openstack image list
```

## Deploy Heat

[![asciicast](https://asciinema.org/a/629807.svg)](https://asciinema.org/a/629807)

### Create secrets

``` shell
kubectl --namespace openstack \
        create secret generic heat-rabbitmq-password \
        --type Opaque \
        --from-literal=username="heat" \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-64};echo;)"
kubectl --namespace openstack \
        create secret generic heat-db-password \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
kubectl --namespace openstack \
        create secret generic heat-admin \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
kubectl --namespace openstack \
        create secret generic heat-trustee \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
kubectl --namespace openstack \
        create secret generic heat-stack-user \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
```

### Run the package deployment

``` shell
cd /opt/genestack/submodules/openstack-helm

helm upgrade --install heat ./heat \
  --namespace=openstack \
    --timeout 120m \
    -f /opt/genestack/helm-configs/heat/heat-helm-overrides.yaml \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.heat.password="$(kubectl --namespace openstack get secret heat-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.heat_trustee.password="$(kubectl --namespace openstack get secret heat-trustee -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.heat_stack_user.password="$(kubectl --namespace openstack get secret heat-stack-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.heat.password="$(kubectl --namespace openstack get secret heat-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.admin.password="$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.heat.password="$(kubectl --namespace openstack get secret heat-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)" \
    --post-renderer /opt/genestack/kustomize/kustomize.sh \
    --post-renderer-args heat/base
```

> In a production like environment you may need to include production specific files like the example variable file found in
  `helm-configs/prod-example-openstack-overrides.yaml`.

### Validate functionality

``` shell
kubectl --namespace openstack exec -ti openstack-admin-client -- openstack --os-interface internal orchestration service list
```

## Deploy Cinder

[![asciicast](https://asciinema.org/a/629808.svg)](https://asciinema.org/a/629808)

### Create secrets

``` shell
kubectl --namespace openstack \
        create secret generic cinder-rabbitmq-password \
        --type Opaque \
        --from-literal=username="cinder" \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-64};echo;)"
kubectl --namespace openstack \
        create secret generic cinder-db-password \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
kubectl --namespace openstack \
        create secret generic cinder-admin \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
```

### Run the package deployment

``` shell
cd /opt/genestack/submodules/openstack-helm

helm upgrade --install cinder ./cinder \
  --namespace=openstack \
    --wait \
    --timeout 120m \
    -f /opt/genestack/helm-configs/cinder/cinder-helm-overrides.yaml \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.cinder.password="$(kubectl --namespace openstack get secret cinder-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.cinder.password="$(kubectl --namespace openstack get secret cinder-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.admin.password="$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.cinder.password="$(kubectl --namespace openstack get secret cinder-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)" \
    --post-renderer /opt/genestack/kustomize/kustomize.sh \
    --post-renderer-args cinder/base
```

> In a production like environment you may need to include production specific files like the example variable file found in
  `helm-configs/prod-example-openstack-overrides.yaml`.

Once the helm deployment is complete cinder and all of it's API services will be online. However, using this setup there will be
no volume node at this point. The reason volume deployments have been disabled is because we didn't expose ceph to the openstack
environment and OSH makes a lot of ceph related assumptions. For testing purposes we're wanting to run with the logical volume
driver (reference) and manage the deployment of that driver in a hybrid way. As such there's a deployment outside of our normal
K8S workflow will be needed on our volume host.

> The LVM volume makes the assumption that the storage node has the required volume group setup `lvmdriver-1` on the node
  This is not something that K8S is handling at this time.

While cinder can run with a great many different storage backends, for the simple case we want to run with the Cinder reference
driver, which makes use of Logical Volumes. Because this driver is incompatible with a containerized work environment, we need
to run the services on our baremetal targets. Genestack has a playbook which will facilitate the installation of our services
and ensure that we've deployed everything in a working order. The playbook can be found at `playbooks/deploy-cinder-volumes-reference.yaml`.
Included in the playbooks directory is an example inventory for our cinder hosts; however, any inventory should work fine.

#### Host Setup

The cinder target hosts need to have some basic setup run on them to make them compatible with our Logical Volume Driver.

1. Ensure DNS is working normally.

Assuming your storage node was also deployed as a K8S node when we did our initial Kubernetes deployment, the DNS should already be
operational for you; however, in the event you need to do some manual tweaking or if the node was note deployed as a K8S worker, then
make sure you setup the DNS resolvers correctly so that your volume service node can communicate with our cluster.

> This is expected to be our CoreDNS IP, in my case this is `169.254.25.10`.

This is an example of my **systemd-resolved** conf found in `/etc/systemd/resolved.conf`
``` conf
[Resolve]
DNS=169.254.25.10
#FallbackDNS=
Domains=openstack.svc.cluster.local svc.cluster.local cluster.local
#LLMNR=no
#MulticastDNS=no
DNSSEC=no
Cache=no-negative
#DNSStubListener=yes
```

Restart your DNS service after changes are made.

``` shell
systemctl restart systemd-resolved.service
```

2. Volume Group `cinder-volumes-1` needs to be created, which can be done in two simple commands.

Create the physical volume

``` shell
pvcreate /dev/vdf
```

Create the volume group

``` shell
vgcreate cinder-volumes-1 /dev/vdf
```

It should be noted that this setup can be tweaked and tuned to your heart's desire; additionally, you can further extend a
volume group with multiple disks. The example above is just that, an example. Check out more from the upstream docs on how
to best operate your volume groups for your specific needs.

#### Hybrid Cinder Volume deployment

With the volume groups and DNS setup on your target hosts, it is now time to deploy the volume services. The playbook `playbooks/deploy-cinder-volumes-reference.yaml` will be used to create a release target for our python code-base and deploy systemd services
units to run the cinder-volume process.

> [!IMPORTANT]
> Consider the **storage** network on your Cinder hosts that will be accessible to Nova compute hosts. By default, the playbook uses `ansible_default_ipv4.address` to configure the target address, which may or may not work for your environment. Append var, i.e., `-e cinder_storage_network_interface=ansible_br_mgmt` to use the specified iface address in `cinder.conf` for `my_ip` and `target_ip_address` in `cinder/backends.conf`. **Interface names with a `-` must be entered with a `_` and be prefixed with `ansible`**

##### Example without storage network interface override

``` shell
ansible-playbook -i inventory-example.yaml deploy-cinder-volumes-reference.yaml
```

Once the playbook has finished executing, check the cinder api to verify functionality.

``` shell
root@openstack-flex-node-0:~# kubectl --namespace openstack exec -ti openstack-admin-client -- openstack volume service list
+------------------+-------------------------------------------------+------+---------+-------+----------------------------+
| Binary           | Host                                            | Zone | Status  | State | Updated At                 |
+------------------+-------------------------------------------------+------+---------+-------+----------------------------+
| cinder-scheduler | cinder-volume-worker                            | nova | enabled | up    | 2023-12-26T17:43:07.000000 |
| cinder-volume    | openstack-flex-node-4.cluster.local@lvmdriver-1 | nova | enabled | up    | 2023-12-26T17:43:04.000000 |
+------------------+-------------------------------------------------+------+---------+-------+----------------------------+
```

> Notice the volume service is up and running with our `lvmdriver-1` target.

At this point it would be a good time to define your types within cinder. For our example purposes we need to define the `lvmdriver-1`
type so that we can schedule volumes to our environment.

``` shell
root@openstack-flex-node-0:~# kubectl --namespace openstack exec -ti openstack-admin-client -- openstack volume type create lvmdriver-1
+-------------+--------------------------------------+
| Field       | Value                                |
+-------------+--------------------------------------+
| description | None                                 |
| id          | 6af6ade2-53ca-4260-8b79-1ba2f208c91d |
| is_public   | True                                 |
| name        | lvmdriver-1                          |
+-------------+--------------------------------------+
```

### Validate functionality

If wanted, create a test volume to tinker with

``` shell
root@openstack-flex-node-0:~# kubectl --namespace openstack exec -ti openstack-admin-client -- openstack volume create --size 1 test
+---------------------+--------------------------------------+
| Field               | Value                                |
+---------------------+--------------------------------------+
| attachments         | []                                   |
| availability_zone   | nova                                 |
| bootable            | false                                |
| consistencygroup_id | None                                 |
| created_at          | 2023-12-26T17:46:15.639697           |
| description         | None                                 |
| encrypted           | False                                |
| id                  | c744af27-fb40-4ffa-8a84-b9f44cb19b2b |
| migration_status    | None                                 |
| multiattach         | False                                |
| name                | test                                 |
| properties          |                                      |
| replication_status  | None                                 |
| size                | 1                                    |
| snapshot_id         | None                                 |
| source_volid        | None                                 |
| status              | creating                             |
| type                | lvmdriver-1                          |
| updated_at          | None                                 |
| user_id             | 2ddf90575e1846368253474789964074     |
+---------------------+--------------------------------------+

root@openstack-flex-node-0:~# kubectl --namespace openstack exec -ti openstack-admin-client -- openstack volume list
+--------------------------------------+------+-----------+------+-------------+
| ID                                   | Name | Status    | Size | Attached to |
+--------------------------------------+------+-----------+------+-------------+
| c744af27-fb40-4ffa-8a84-b9f44cb19b2b | test | available |    1 |             |
+--------------------------------------+------+-----------+------+-------------+
```

You can validate the environment is operational by logging into the storage nodes to validate the LVM targets are being created.

``` shell
root@openstack-flex-node-4:~# lvs
  LV                                   VG               Attr       LSize Pool Origin Data%  Meta%  Move Log Cpy%Sync Convert
  c744af27-fb40-4ffa-8a84-b9f44cb19b2b cinder-volumes-1 -wi-a----- 1.00g
```

## Create Compute Kit Secrets

[![asciicast](https://asciinema.org/a/629813.svg)](https://asciinema.org/a/629813)

### Creating the Compute Kit Secrets

Part of running Nova is also running placement. Setup all credentials now so we can use them across the nova and placement services.

``` shell
# Shared
kubectl --namespace openstack \
        create secret generic metadata-shared-secret \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
```

``` shell
# Placement
kubectl --namespace openstack \
        create secret generic placement-db-password \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
kubectl --namespace openstack \
        create secret generic placement-admin \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
```

``` shell
# Nova
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
```

``` shell
# Ironic (NOT IMPLEMENTED YET)
kubectl --namespace openstack \
        create secret generic ironic-admin \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
```

``` shell
# Designate (NOT IMPLEMENTED YET)
kubectl --namespace openstack \
        create secret generic designate-admin \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
```

``` shell
# Neutron
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

### Deploy Placement

``` shell
cd /opt/genestack/submodules/openstack-helm

helm upgrade --install placement ./placement --namespace=openstack \
  --namespace=openstack \
    --timeout 120m \
    -f /opt/genestack/helm-configs/placement/placement-helm-overrides.yaml \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.placement.password="$(kubectl --namespace openstack get secret placement-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.placement.password="$(kubectl --namespace openstack get secret placement-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.nova_api.password="$(kubectl --namespace openstack get secret nova-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --post-renderer /opt/genestack/kustomize/kustomize.sh \
    --post-renderer-args placement/base
```

### Deploy Nova

``` shell
cd /opt/genestack/submodules/openstack-helm

helm upgrade --install nova ./nova \
  --namespace=openstack \
    --timeout 120m \
    -f /opt/genestack/helm-configs/nova/nova-helm-overrides.yaml \
    --set conf.nova.neutron.metadata_proxy_shared_secret="$(kubectl --namespace openstack get secret metadata-shared-secret -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.nova.password="$(kubectl --namespace openstack get secret nova-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.neutron.password="$(kubectl --namespace openstack get secret neutron-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.ironic.password="$(kubectl --namespace openstack get secret ironic-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.placement.password="$(kubectl --namespace openstack get secret placement-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.cinder.password="$(kubectl --namespace openstack get secret cinder-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.nova.password="$(kubectl --namespace openstack get secret nova-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db_api.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db_api.auth.nova.password="$(kubectl --namespace openstack get secret nova-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db_cell0.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db_cell0.auth.nova.password="$(kubectl --namespace openstack get secret nova-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.admin.password="$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.nova.password="$(kubectl --namespace openstack get secret nova-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)" \
    --post-renderer /opt/genestack/kustomize/kustomize.sh \
    --post-renderer-args nova/base
```

> In a production like environment you may need to include production specific files like the example variable file found in
  `helm-configs/prod-example-openstack-overrides.yaml`.

> NOTE: The above command is setting the ceph as disabled. While the K8S infrastructure has Ceph,
  we're not exposing ceph to our openstack environment.

If running in an environment that doesn't have hardware virtualization extensions add the following two `set` switches to the install command.

``` shell
--set conf.nova.libvirt.virt_type=qemu --set conf.nova.libvirt.cpu_mode=none
```

> In a production like environment you may need to include production specific files like the example variable file found in
  `helm-configs/prod-example-openstack-overrides.yaml`.

### Deploy Neutron

``` shell
cd /opt/genestack/submodules/openstack-helm

helm upgrade --install neutron ./neutron \
  --namespace=openstack \
    --timeout 120m \
    -f /opt/genestack/helm-configs/neutron/neutron-helm-overrides.yaml \
    --set conf.metadata_agent.DEFAULT.metadata_proxy_shared_secret="$(kubectl --namespace openstack get secret metadata-shared-secret -o jsonpath='{.data.password}' | base64 -d)" \
    --set conf.ovn_metadata_agent.DEFAULT.metadata_proxy_shared_secret="$(kubectl --namespace openstack get secret metadata-shared-secret -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.neutron.password="$(kubectl --namespace openstack get secret neutron-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.nova.password="$(kubectl --namespace openstack get secret nova-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.placement.password="$(kubectl --namespace openstack get secret placement-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.designate.password="$(kubectl --namespace openstack get secret designate-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.ironic.password="$(kubectl --namespace openstack get secret ironic-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.neutron.password="$(kubectl --namespace openstack get secret neutron-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.admin.password="$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.neutron.password="$(kubectl --namespace openstack get secret neutron-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set conf.neutron.ovn.ovn_nb_connection="tcp:$(kubectl --namespace kube-system get service ovn-nb -o jsonpath='{.spec.clusterIP}:{.spec.ports[0].port}')" \
    --set conf.neutron.ovn.ovn_sb_connection="tcp:$(kubectl --namespace kube-system get service ovn-sb -o jsonpath='{.spec.clusterIP}:{.spec.ports[0].port}')" \
    --set conf.plugins.ml2_conf.ovn.ovn_nb_connection="tcp:$(kubectl --namespace kube-system get service ovn-nb -o jsonpath='{.spec.clusterIP}:{.spec.ports[0].port}')" \
    --set conf.plugins.ml2_conf.ovn.ovn_sb_connection="tcp:$(kubectl --namespace kube-system get service ovn-sb -o jsonpath='{.spec.clusterIP}:{.spec.ports[0].port}')" \
    --post-renderer /opt/genestack/kustomize/kustomize.sh \
    --post-renderer-args neutron/base
```

> In a production like environment you may need to include production specific files like the example variable file found in
  `helm-configs/prod-example-openstack-overrides.yaml`.

> The above command derives the OVN north/south bound database from our K8S environment. The insert `set` is making the assumption we're using **tcp** to connect.

## Deploy Octavia

[![asciicast](https://asciinema.org/a/629814.svg)](https://asciinema.org/a/629814)

### Create secrets

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

### Run the package deployment

``` shell
cd /opt/genestack/submodules/openstack-helm

helm upgrade --install octavia ./octavia \
    --namespace=openstack \
    --wait \
    --timeout 120m \
    -f /opt/genestack/helm-configs/octavia/octavia-helm-overrides.yaml \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.octavia.password="$(kubectl --namespace openstack get secret octavia-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.octavia.password="$(kubectl --namespace openstack get secret octavia-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.admin.password="$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.octavia.password="$(kubectl --namespace openstack get secret octavia-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set conf.octavia.certificates.ca_private_key_passphrase="$(kubectl --namespace openstack get secret octavia-certificates -o jsonpath='{.data.password}' | base64 -d)" \
    --set conf.octavia.ovn.ovn_nb_connection="tcp:$(kubectl --namespace kube-system get service ovn-nb -o jsonpath='{.spec.clusterIP}:{.spec.ports[0].port}')" \
    --set conf.octavia.ovn.ovn_sb_connection="tcp:$(kubectl --namespace kube-system get service ovn-sb -o jsonpath='{.spec.clusterIP}:{.spec.ports[0].port}')" \
    --post-renderer /opt/genestack/kustomize/kustomize.sh \
    --post-renderer-args octavia/base
```

> In a production like environment you may need to include production specific files like the example variable file found in
  `helm-configs/prod-example-openstack-overrides.yaml`.

Now validate functionality

``` shell

```

## Deploy Horizon

[![asciicast](https://asciinema.org/a/629815.svg)](https://asciinema.org/a/629815)

### Create secrets

``` shell
kubectl --namespace openstack \
        create secret generic horizon-secrete-key \
        --type Opaque \
        --from-literal=username="horizon" \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-64};echo;)"
kubectl --namespace openstack \
        create secret generic horizon-db-password \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
```

### Run the package deployment

``` shell
cd /opt/genestack/submodules/openstack-helm

helm upgrade --install horizon ./horizon \
    --namespace=openstack \
    --wait \
    --timeout 120m \
    -f /opt/genestack/helm-configs/horizon/horizon-helm-overrides.yaml \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set conf.horizon.local_settings.config.horizon_secret_key="$(kubectl --namespace openstack get secret horizon-secrete-key -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.horizon.password="$(kubectl --namespace openstack get secret horizon-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --post-renderer /opt/genestack/kustomize/kustomize.sh \
    --post-renderer-args horizon/base
```

> In a production like environment you may need to include production specific files like the example variable file found in
  `helm-configs/prod-example-openstack-overrides.yaml`.

## Deploy Skyline

[![asciicast](https://asciinema.org/a/629816.svg)](https://asciinema.org/a/629816)

Skyline is an alternative Web UI for OpenStack. If you deploy horizon there's no need for Skyline.

### Create secrets

Skyline is a little different because there's no helm integration. Given this difference the deployment is far simpler, and all secrets can be managed in one object.

``` shell
kubectl --namespace openstack \
        create secret generic skyline-apiserver-secrets \
        --type Opaque \
        --from-literal=service-username="skyline" \
        --from-literal=service-password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)" \
        --from-literal=service-domain="service" \
        --from-literal=service-project="service" \
        --from-literal=service-project-domain="service" \
        --from-literal=db-endpoint="mariadb-galera-primary.openstack.svc.cluster.local" \
        --from-literal=db-name="skyline" \
        --from-literal=db-username="skyline" \
        --from-literal=db-password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)" \
        --from-literal=secret-key="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)" \
        --from-literal=keystone-endpoint="http://keystone-api.openstack.svc.cluster.local:5000" \
        --from-literal=default-region="RegionOne"
```

> Note all the configuration is in this one secret, so be sure to set your entries accordingly.

### Run the deployment

> [!TIP]
> Pause for a moment to consider if you will be wanting to access Skyline via your ingress controller over a specific FQDN. If so, modify `/opt/genestack/kustomize/skyline/fqdn/kustomization.yaml` to suit your needs then use `fqdn` below in lieu of `base`...

``` shell
kubectl --namespace openstack apply -k /opt/genestack/kustomize/skyline/base
```
