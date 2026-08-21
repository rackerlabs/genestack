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

- A valid `clouds.yaml` with credentials for your project (e.g., `acme-corp`)
- The OpenStack CLI installed and configured

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
  "acme-corp-network"
```

### Create the subnet

``` shell
openstack subnet create \
  --project="acme-corp" \
  --dhcp \
  --network="acme-corp-network" \
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

!!! tip

    If accessing the application server through jump hosts, copy the private key (`acme_corp_ssh_key`) to `~/.ssh/` on each jump host and set permissions with `chmod 600`.

### Create security groups

Create a security group for the application server (allows SSH):

``` shell
openstack security group create \
  --description "Security group for ACME Corp application server" \
  acme-corp-app-secgroup

openstack security group rule create --protocol icmp --remote-ip 0.0.0.0/0 acme-corp-app-secgroup
openstack security group rule create --protocol tcp --dst-port 22 --remote-ip 0.0.0.0/0 acme-corp-app-secgroup
```

### Launch the application server

``` shell
openstack server create \
  --flavor m1.small \
  --image "Ubuntu 22.04 LTS" \
  --nic net-id=acme-corp-network \
  --key-name acme-corp-keypair \
  --security-group acme-corp-app-secgroup \
  acme-corp-app-server
```

### Create the database instance

``` shell
openstack database instance create \
  --flavor m1.small \
  --size 10 \
  --databases acme_db \
  --users acme_user:acme_pwd \
  --datastore mysql \
  --datastore-version-number 8.4 \
  --nic net-id=$(openstack network list -f value | grep acme-corp-network | awk '{print $1}') \
  --allowed-cidr $(openstack subnet show acme-corp-subnet -f value -c cidr) \
  acme-corp-db-server
```

### Connect from the application server

Once all resources are active, SSH into the application server and connect to the database:

``` shell
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
  --databases acme_db \
  --users acme_user:acme_pwd \
  --datastore mysql \
  --datastore-version-number 8.4 \
  --nic net-id=$(openstack network list -f value | grep acme-corp-network | awk '{print $1}') \
  --allowed-cidr $(openstack subnet show acme-corp-subnet -f value -c cidr) \
  --is-public \
  acme-corp-db-pub-server
```

Create a security group for the database instance (allows MySQL on port 3306):

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
mysql --host=<FLOATING_IP> --user=acme_user --password=acme_pwd
```

!!! tip "Scaling with multiple database replicas"

    When using read replicas, you can add multiple Trove instances as members of the same pool. The `ROUND_ROBIN` algorithm will distribute connections across all healthy members.
