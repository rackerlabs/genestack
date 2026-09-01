# Trove Database Access

This guide covers the different methods for connecting to OpenStack Trove database instances. Depending on your role and network requirements, choose the access method that best fits your use case.

| Access Method | Audience | Network Path |
|---|---|---|
| [Local host access](#local-host-access) | Developers, engineers, support personnel | Direct SSH to guest instance |
| [Tenant network access](#tenant-network-access-from-an-application-server) | Customers, developers | Private tenant network |
| [Public access (direct)](#public-access-directly-to-a-database-instance) | Customers, external applications | Public IP on DB instance |
| [Public access (load balancer)](#public-access-to-a-database-behind-a-load-balancer) | Customers, production workloads | Load balancer with floating IP |

---

## Local Host Access

!!! note "Internal use only"

    This method is intended for developers, engineers, and support personnel who have SSH access to the underlying infrastructure. It is not available to end-user tenants.

A localhost database connection can be achieved by executing the following steps:

1. SSH into the Trove guest instance:

    ``` shell
    /opt/genestack/scripts/trove-guest-ssh.sh <DB_INSTANCE_ID>
    ```

2. Enter the database container (always named `database`):

    ``` shell
    docker exec -it database bash
    ```

3. Connect to MySQL using the `os_admin` credentials:

    ``` shell
    mysql
    ```

    This uses the credentials stored in `/var/lib/mysql/conf.d/os_admin.cnf`.

---

## Tenant Network Access from an Application Server

This method demonstrates how a tenant application server can connect to a Trove database instance over a shared private network. This is the most common pattern for production application-to-database communication.

### Prerequisites

- The OpenStack CLI installed and configured

### Create tenant and clouds.yaml
``` shell
AUTH_URL=$(openstack endpoint list --service keystone --interface internal -f value -c URL)
TENANT=acme-corp
USERNAME="${TENANT}-admin"
PASSWORD="${USERNAME}-pwd"
openstack  project create "${TENANT}" --domain default --description "Test tenant: ${TENANT}"
openstack user create "${USERNAME}" --domain default --project "${TENANT}" --password "${PASSWORD}" --description "Admin user for ${TENANT}"
openstack user set "${USERNAME}" --password "${PASSWORD}"
openstack role add --project "${TENANT}" --user "${USERNAME}" member 2>/dev/null || true
openstack role add --project "${TENANT}" --user "${USERNAME}" admin 2>/dev/null || true
cat > "clouds.yaml" << CLOUDS_YAML_EOF
clouds:
  ${TENANT}:
    auth:
      auth_url: ${AUTH_URL}
      project_name: ${TENANT}
      project_domain_name: Default
      username: ${USERNAME}
      user_domain_name: Default
      password: ${PASSWORD}
    region_name: RegionOne
    interface: internal
    identity_api_version: 3
CLOUDS_YAML_EOF
chmod 0640 "clouds.yaml"
```
### Set the target cloud

``` shell
export OS_CLOUD=acme-corp
```

### Create the tenant network

``` shell
openstack network create \
  --project="acme-corp" \
  --provider-network-type=geneve \
  --internal \
  --enable-port-security \
  --enable \
  "acme-corp-net"
```

### Create the subnet

``` shell
openstack subnet create \
  --project="acme-corp" \
  --dhcp \
  --network="acme-corp-net" \
  --subnet-range=192.168.50.0/24 \
  --gateway=192.168.50.1 \
  --dns-nameserver 1.1.1.1 \
  --dns-nameserver 8.8.8.8 \
  "acme-corp-subnet"
```

### Create and attach the router

``` shell
openstack router create \
  --project="acme-corp" \
  --external-gateway flat \
  "acme-corp-router"
```

``` shell
openstack router add subnet "acme-corp-router" "acme-corp-subnet"
```

### Create an SSH keypair

Generate an SSH key and register it with OpenStack for access to the application server:

``` shell
ssh-keygen -qt ed25519 -N '' -C "acme_corp_ssh" -f ./acme_corp_ssh_key
openstack keypair create --public-key ./acme_corp_ssh_key.pub acme-corp-keypair
cp acme_corp_ssh_key* ~/.ssh/
```

!!! note

    The private key (`acme_corp_ssh_key`) needs to exist on each compute host, so execute the following on each compute host:
``` shell
    > cat ~/.ssh/acme_corp_ssh_key | ssh ubuntu@<COMPUTE_HOST_NAME> "cat > ~/.ssh/acme_corp_ssh_key && chmod 600 ~/.ssh/acme_corp_ssh_key"
```

### Create security groups

Create a security group for the application server (allows SSH):

``` shell
openstack security group create \
  --description "Security group for ACME Corp application server" \
  acme-corp-app-secgroup

openstack security group rule create --protocol icmp --remote-ip 0.0.0.0/0 acme-corp-app-secgroup
openstack security group rule create --protocol tcp --dst-port 22 --remote-ip 0.0.0.0/0 acme-corp-app-secgroup
```

### Load an Ubuntu image (need for application server build in next step)

``` shell
pushd /tmp
wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
openstack --os-cloud default image create \
  --disk-format qcow2 \
  --container-format bare \
  --file jammy-server-cloudimg-amd64.img \
  --property os_distro='ubuntu' \
  --property os_version='22.04' \
  --property hw_disk_bus='scsi' \
  --property hw_scsi_model='virtio-scsi' \
  --public \
  "Ubuntu 22.04 LTS"
popd
```

### Launch the application server

``` shell
openstack server create \
  --flavor m1.small \
  --image "Ubuntu 22.04 LTS" \
  --nic net-id=acme-corp-net \
  --key-name acme-corp-keypair \
  --security-group acme-corp-app-secgroup \
  acme-corp-app-server
```

### Create a private database instance

``` shell
openstack database instance create \
  --flavor m1.small \
  --size 10 \
  --databases acme_db \
  --users acme_user:acme_pwd \
  --datastore mysql \
  --datastore-version-number 8.4 \
  --nic net-id=$(openstack network list -f value | grep acme-corp-net | awk '{print $1}') \
  --allowed-cidr $(openstack subnet show acme-corp-subnet -f value -c cidr) \
  acme-corp-db-server
```

### Connect from the application server

Once all resources are active, SSH into the application server and connect to the database:

``` shell
sudo apt update
sudo apt install mysql-client-core-8.0
mysql --host=<DB_INSTANCE_IP> --user=acme_user --password=acme_pwd
```

Replace `<DB_INSTANCE_IP>` with the private IP address of the database instance shown in `openstack database instance show acme-corp-db-server`.

---

## Public Access Directly to a Database Instance

Public access to a database instance on a tenant network can be achieved by passing the `--is-public` flag during instance creation. This assigns a publicly routable IP directly to the instance.

``` shell
openstack database instance create \
  --flavor m1.small \
  --size 10 \
  --databases acme_pub_db \
  --users acme_user:acme_pwd \
  --datastore mysql \
  --datastore-version-number 8.4 \
  --nic net-id=$(openstack network list -f value | grep acme-corp-net | awk '{print $1}') \
  --allowed-cidr $(openstack subnet show acme-corp-subnet -f value -c cidr) \
  --is-public \
  acme-corp-pub-db-server
```

Create a security group for the database instance (allows MySQL on port 3306 from IPs outside the tenant network):

``` shell
openstack security group create \
  --description "Security group for public ACME Corp database instances" \
  acme-corp-pub-db-secgroup

openstack security group rule create --protocol icmp --remote-ip 0.0.0.0/0 acme-corp-pub-db-secgroup
openstack security group rule create --protocol tcp --dst-port 3306 --remote-ip 0.0.0.0/0 acme-corp-pub-db-secgroup
```

Attach the database security group to the Trove instance:

``` shell
openstack server add security group \
  $(openstack database instance show acme-corp-pub-db-server -f json | jq -r '.server_id') \
  acme-corp-pub-db-secgroup
```

Once the instance is active, connect from any external location:

``` shell
sudo apt update
sudo apt install mysql-client-core-8.0
mysql --host=<PUBLIC_DB_IP> --user=acme_user --password=acme_pwd
```

!!! warning "Security consideration"

    Exposing a database instance directly to the public internet increases the attack surface. Ensure that appropriate security groups are in place and consider using strong credentials, TLS, and IP allowlists.

---

## Public Access to a Database Behind a Load Balancer

For production workloads that require high availability or connection pooling, you can place a Trove database instance behind an Octavia load balancer and expose it via a floating IP.

This approach keeps the database on a private subnet while providing controlled public access through the load balancer.

### Create the load balancer

``` shell
openstack loadbalancer create \
  --name acme-corp-db-lb \
  --vip-subnet-id acme-corp-subnet \
  --vip-sg-id acme-corp-pub-db-secgroup
```

Wait for the load balancer to become `ACTIVE`:

``` shell
openstack loadbalancer list
```

### Create a listener

``` shell
openstack loadbalancer listener create \
  --name acme-corp-db-listener \
  --protocol TCP \
  --protocol-port 3306 \
  acme-corp-db-lb
```

Wait for the listener to become `ACTIVE`:

``` shell
openstack loadbalancer listener show acme-corp-db-listener
```

### Create a pool

``` shell
openstack loadbalancer pool create \
  --name acme-corp-db-pool \
  --listener acme-corp-db-listener \
  --protocol TCP \
  --lb-algorithm ROUND_ROBIN
```

Wait for the pool to become `ACTIVE`:

``` shell
openstack loadbalancer pool list
```

### Add the database instance as a member

``` shell
openstack loadbalancer member create \
  --address <DB_INSTANCE_IP> \
  --protocol-port 3306 \
  acme-corp-db-pool
```

Wait for the member to become `ACTIVE`:

``` shell
openstack loadbalancer member list acme-corp-db-pool
```

### Assign a floating IP to the load balancer

Retrieve the VIP port ID and associate a floating IP:

``` shell
openstack loadbalancer show acme-corp-db-lb -c vip_port_id
openstack floating ip create <EXTERNAL_NETWORK> --port <VIP_PORT_ID>
```

Replace `<EXTERNAL_NETWORK>` with the name of your external/public provider network, and `<VIP_PORT_ID>` with the value from the previous command.

### Connect through the load balancer

Once the floating IP is associated, connect from any external location:

``` shell
sudo apt update
sudo apt install mysql-client-core-8.0
mysql --host=<FLOATING_IP> --user=acme_user --password=acme_pwd
```

!!! tip "Scaling with multiple database replicas"

    When using read replicas, you can add multiple Trove instances as members of the same pool. The `ROUND_ROBIN` algorithm will distribute connections across all healthy members.
