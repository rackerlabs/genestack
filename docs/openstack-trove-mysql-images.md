# Building MySQL Images for Trove

This guide explains how to build and configure MySQL database images for use with OpenStack Trove Database as a Service.

## Overview

Trove requires pre-built database images that contain the database software and the Trove guest agent. This document covers building MySQL 8.4 images and configuring them for use with Trove.

## Prerequisites

### System Requirements

- Ubuntu 22.04 or later (recommended)
- At least 10GB free disk space
- 4GB RAM minimum
- Internet connection for downloading packages

### Required Packages

Install the required packages on your build system:

```bash
sudo apt-get update
sudo apt-get install -y \
    qemu-utils \
    libguestfs-tools \
    wget \
    curl \
    python3-openstackclient
```

### OpenStack Environment

Ensure you have:
- Access to an OpenStack environment with Trove deployed
- OpenStack credentials configured
- Glance service available for image uploads

## Building MySQL 8.4 Image

### Automated Build Process

Use the provided script to build a MySQL 8.4 image:

```bash
# Basic build with defaults
/opt/genestack/scripts/build-trove-mysql-image.sh

# Custom build with specific parameters
IMAGE_NAME="my-mysql-8.4" \
IMAGE_SIZE="10G" \
WORK_DIR="/tmp/my-build" \
/opt/genestack/scripts/build-trove-mysql-image.sh
```

### Build Process Details

The build script performs the following steps:

1. **Downloads Ubuntu 22.04 cloud image** as the base
2. **Installs MySQL 8.4** from the official MySQL APT repository
3. **Configures MySQL** for Trove compatibility
4. **Installs Trove guest agent** from the stable/2024.2 branch
5. **Configures cloud-init** for proper initialization
6. **Creates systemd services** for automatic startup
7. **Optimizes the image** and uploads to Glance

### Manual Build Process

If you prefer to build manually:

```bash
# Create working directory
mkdir -p /tmp/trove-build
cd /tmp/trove-build

# Download base image
wget https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.img

# Copy and resize
cp ubuntu-22.04-server-cloudimg-amd64.img mysql-8.4-base.qcow2
qemu-img resize mysql-8.4-base.qcow2 5G

# Customize with virt-customize
virt-customize -a mysql-8.4-base.qcow2 \
    --run-command 'apt-get update && apt-get upgrade -y' \
    --install python3,python3-pip,mysql-server \
    --run-command 'pip3 install python-troveclient' \
    # ... additional customization commands
```

## Image Configuration

### MySQL Configuration

The image includes optimized MySQL settings in `/etc/mysql/mysql.conf.d/trove.cnf`:

```ini
[mysqld]
bind-address = 0.0.0.0
log-bin = mysql-bin
server-id = 1
binlog-format = ROW
default-storage-engine = InnoDB
innodb_file_per_table = 1
collation-server = utf8_general_ci
character-set-server = utf8
max_connections = 1000
max_allowed_packet = 1G
```

### Trove Guest Agent Configuration

The guest agent configuration is located at `/etc/trove/trove-guestagent.conf`:

```ini
[DEFAULT]
log_file = /var/log/trove/trove-guestagent.log
debug = True
control_exchange = trove
trove_auth_url = http://keystone-api.openstack.svc.cluster.local:5000/v3
rpc_backend = rabbit
rabbit_host = rabbitmq.openstack.svc.cluster.local
rabbit_userid = trove
rabbit_password = password
rabbit_virtual_host = trove

[mysql]
root_password = root
default_password_length = 36
```

## Uploading to Glance

### Automatic Upload

The build script automatically uploads the image to Glance if OpenStack credentials are configured:

```bash
# Ensure credentials are set
source /path/to/openrc

# Build and upload
/opt/genestack/scripts/build-trove-mysql-image.sh
```

### Manual Upload

Upload the image manually:

```bash
openstack image create \
    --disk-format qcow2 \
    --container-format bare \
    --public \
    --property os_type=linux \
    --property os_distro=ubuntu \
    --property os_version=22.04 \
    --property trove_datastore=mysql \
    --property trove_datastore_version=8.4 \
    --file /tmp/trove-image-build/trove-mysql-8.4.qcow2 \
    trove-mysql-8.4
```

## Configuring Trove Datastores

After uploading the image, configure Trove to use it:

### Automated Setup

Use the provided setup script:

```bash
/opt/genestack/scripts/setup-trove-datastores.sh
```

### Manual Configuration

1. **Create the datastore**:
```bash
openstack datastore create mysql
```

2. **Create datastore versions**:
```bash
# Get image ID
IMAGE_ID=$(openstack image show trove-mysql-8.4 -f value -c id)

# Create version
openstack datastore version create \
    --datastore mysql \
    --image $IMAGE_ID \
    --packages mysql-server \
    --active \
    8.4 \
    8.4
```

3. **Create default configuration**:
```bash
openstack database configuration create \
    --datastore mysql \
    --datastore-version 8.4 \
    --description "Default MySQL 8.4 configuration" \
    mysql-default-config \
    '{"max_connections": 1000, "innodb_buffer_pool_size": "75%"}'
```

## Testing the Image

### Create Test Instance

Create a test database instance to verify the image works:

```bash
# Create instance
openstack database instance create \
    --flavor db.small \
    --size 10 \
    --datastore mysql \
    --datastore-version 8.4 \
    --nic net-id=$(openstack network list --internal -f value -c ID | head -n1) \
    test-mysql-instance

# Check status
openstack database instance show test-mysql-instance

# List instances
openstack database instance list
```

### Verify Database Functionality

Once the instance is active:

```bash
# Create a database
openstack database db create test-mysql-instance testdb

# Create a user
openstack database user create test-mysql-instance testuser testpass --databases testdb

# List databases
openstack database db list test-mysql-instance

# List users
openstack database user list test-mysql-instance
```

## Troubleshooting

### Common Issues

1. **Image build fails**:
   - Check disk space (need at least 10GB free)
   - Verify internet connectivity
   - Check libguestfs-tools installation

2. **Upload to Glance fails**:
   - Verify OpenStack credentials
   - Check Glance service availability
   - Ensure sufficient quota

3. **Instance creation fails**:
   - Verify datastore configuration
   - Check flavor availability
   - Ensure network connectivity

### Debug Instance Issues

Check instance logs:

```bash
# Get instance details
openstack database instance show test-mysql-instance

# Check Nova instance logs
nova_instance_id=$(openstack database instance show test-mysql-instance -f value -c server_id)
openstack server show $nova_instance_id
openstack console log show $nova_instance_id
```

### Guest Agent Logs

Access guest agent logs from within the instance:

```bash
# SSH to instance (if accessible)
tail -f /var/log/trove/trove-guestagent.log

# Check service status
systemctl status trove-guestagent
systemctl status mysql
```

## Advanced Configuration

### Custom MySQL Versions

To build images for different MySQL versions:

```bash
MYSQL_VERSION="8.0" \
IMAGE_NAME="trove-mysql-8.0" \
/opt/genestack/scripts/build-trove-mysql-image.sh
```

### Performance Tuning

Modify the MySQL configuration in the build script for specific workloads:

```ini
# For high-performance workloads
innodb_buffer_pool_size = 80%
innodb_log_file_size = 256M
innodb_flush_log_at_trx_commit = 2
sync_binlog = 0
```

### Security Hardening

Additional security configurations:

```ini
# Security settings
skip-symbolic-links
local-infile = 0
secure-file-priv = /var/lib/mysql-files/
sql_mode = STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION
```

## Best Practices

1. **Regular Updates**: Rebuild images regularly with security updates
2. **Version Management**: Maintain separate images for different MySQL versions
3. **Testing**: Always test images before production use
4. **Monitoring**: Monitor guest agent logs for issues
5. **Backup**: Ensure proper backup strategies for database instances

## Integration with Genestack

The MySQL image building process integrates with the Genestack deployment:

1. **Automated Builds**: Include in CI/CD pipelines
2. **Version Management**: Track image versions with Helm chart versions
3. **Configuration Management**: Use Kustomize overlays for environment-specific settings
4. **Monitoring**: Integrate with existing monitoring stack

For more information on Trove deployment and management, see the [OpenStack Trove documentation](openstack-trove.md).