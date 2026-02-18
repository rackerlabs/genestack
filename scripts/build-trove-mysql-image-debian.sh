#!/bin/bash
set -e

# MySQL 8.4 Trove Image Builder Script
# This script builds a MySQL 8.4 qcow2 image for use with OpenStack Trove
# with SSH and ping access enabled

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${WORK_DIR:-/tmp/trove-image-build-debian}"
IMAGE_NAME="${IMAGE_NAME:-trove-mysql-8.4-debian}"
IMAGE_SIZE="${IMAGE_SIZE:-10G}"
MYSQL_VERSION="${MYSQL_VERSION:-8.4}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

check_dependencies() {
    log "Checking dependencies..."

    local deps=("qemu-utils" "libguestfs-tools" "wget" "curl")
    for dep in "${deps[@]}"; do
        if dpkg -s $dep &>/dev/null; then
            log "$dep is installed."
        else
            warn "$dep is required but not installed. Installing now..."
            DEBIAN_FRONTEND=noninteractive apt-get install -y $dep
        fi
    done

    log "All dependencies satisfied"
}

prepare_workspace() {
    log "Preparing workspace at $WORK_DIR"
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"
}

download_base_image() {
    log "Downloading Debian generic cloud image..."

    # https://cdimage.debian.org/images/cloud/bookworm/20260129-2372/debian-12-generic-amd64-20260129-2372.qcow2
    local base_image_url="https://cdimage.debian.org/images/cloud/bookworm/20260129-2372/debian-12-generic-amd64-20260129-2372.qcow2"
    local base_image="debian-12-generic-amd64-20260129-2372.qcow2"
    
    if [ ! -f "$base_image" ]; then
        wget -O "$base_image" "$base_image_url" || error "Failed to download base image"
    else
        log "Base image already exists, skipping download"
    fi
    
    # Create working copy
    cp "$base_image" "${IMAGE_NAME}-working-copy.qcow2"
    cp "$base_image" "${IMAGE_NAME}-base.qcow2"

    # Resize image
    log "Resizing image to $IMAGE_SIZE"
    qemu-img resize "${IMAGE_NAME}-base.qcow2" "$IMAGE_SIZE"
#    LIBGUESTFS_DEBUG=1 LIBGUESTFS_TRACE=1 virt-resize --expand /dev/sda1 "${IMAGE_NAME}-working-copy.qcow2" "${IMAGE_NAME}-base.qcow2"
    virt-resize --expand /dev/sda1 "${IMAGE_NAME}-working-copy.qcow2" "${IMAGE_NAME}-base.qcow2"
}

create_trove_guest_script() {
    log "Creating Trove guest agent installation script..."
    
    cat > trove-guest-setup.sh << 'SCRIPT_EOF'
#!/bin/sh
set -e

date > /tmp/debug_build_output.txt ; echo "Building Trove MySQL 8.4 Image..." >> /tmp/debug_build_output.txt

# Update system
echo "[DEBUG] Updating and upgrading apt"
date >> /tmp/debug_build_output.txt ; echo "Updating and upgrading apt" >> /tmp/debug_build_output.txt
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

# Install required packages
echo "[DEBUG] Installing required packages"
date >> /tmp/debug_build_output.txt ; echo "Installing required packages" >> /tmp/debug_build_output.txt
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    python3 \
    python3-pip \
    python3-dev \
    python3-venv \
    git \
    curl \
    wget \
    software-properties-common \
    gnupg \
    lsb-release \
    ca-certificates \
    cloud-init \
    cloud-utils \
    cloud-guest-utils \
    openssh-server \
    iputils-ping \
    net-tools \
    iproute2 \
    iptables \
    sudo \
    vim \
    less \
    build-essential \
    libssl-dev \
    libffi-dev \
    default-libmysqlclient-dev \
    pkg-config

# Enable and configure SSH
echo "[DEBUG] Enabling and configuring SSH"
date >> /tmp/debug_build_output.txt ; echo "Enabling and configuring SSH" >> /tmp/debug_build_output.txt
systemctl enable ssh

# Configure SSH to allow password authentication and root login (for debugging)
#sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
#sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
#echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
#echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config

# Enable ICMP (ping) by ensuring firewall allows it
echo "[DEBUG] Configuring firewall for ping"
date >> /tmp/debug_build_output.txt ; echo "Configuring firewall for ping" >> /tmp/debug_build_output.txt
# Ensure iptables allows ICMP
iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT
iptables -A OUTPUT -p icmp --icmp-type echo-reply -j ACCEPT

# Download and configure MySQL APT repository
echo ---
echo "[DEBUG] /etc/resolv.conf:"
cat /etc/resolv.conf
echo 'nameserver 8.8.8.8' > /etc/resolv.conf
echo "[DEBUG] /etc/resolv.conf:"
cat /etc/resolv.conf
echo ---
ip a
echo ---
ip route
echo ---
PING_OUT=$(ping 8.8.8.8 -c 1) || true
echo ${PING_OUT}
echo ---
echo "[DEBUG] Installing MySQL apt config"
date >> /tmp/debug_build_output.txt ; echo "Installing MySQL apt config" >> /tmp/debug_build_output.txt
wget https://dev.mysql.com/get/mysql-apt-config_0.8.36-1_all.deb
DEBIAN_FRONTEND=noninteractive dpkg -i mysql-apt-config_0.8.36-1_all.deb || true
apt-get update

# Install Trove Client
echo "[DEBUG] Installing Trove guest agent"
date >> /tmp/debug_build_output.txt ; echo "Installing Trove client" >> /tmp/debug_build_output.txt
mkdir -p /usr/local/venv
python3 -m venv /usr/local/venv/trove
. /usr/local/venv/trove/bin/activate
pip3 install --upgrade pip setuptools wheel
pip3 install python-troveclient

# Clone and install trove guest agent
date >> /tmp/debug_build_output.txt ; echo "Installing Trove from source" >> /tmp/debug_build_output.txt
cd /opt
git clone https://opendev.org/openstack/trove.git -b stable/2025.1
cd trove
pip3 install -e . --ignore-installed

# Create trove user
echo "[DEBUG] Creating Trove user"
date >> /tmp/debug_build_output.txt ; echo "Creating Trove user" >> /tmp/debug_build_output.txt
useradd -m -s /bin/bash trove || true
echo "trove:trove-pwd" | chpasswd
usermod -aG sudo trove
echo "trove ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/trove

# Create trove directories
echo "[DEBUG] Creating Trove directories"
date >> /tmp/debug_build_output.txt ; echo "Creating Trove directories" >> /tmp/debug_build_output.txt
mkdir -p /etc/trove
mkdir -p /var/log/trove
mkdir -p /var/lib/trove
chown -R trove:trove /etc/trove /var/log/trove /var/lib/trove

# Create trove guest configuration
echo "[DEBUG] Creating Trove guest configuration"
date >> /tmp/debug_build_output.txt ; echo "Creating Trove guest configuration" >> /tmp/debug_build_output.txt
cat > /etc/trove/trove-guestagent.conf << 'TROVE_EOF'
[DEFAULT]
log_file = /var/log/trove/trove-guestagent.log
log_dir = /var/log/trove
debug = True
verbose = True
control_exchange = trove
trove_auth_url = http://keystone-api.openstack.svc.cluster.local:5000/v3
nova_proxy_admin_user = admin
nova_proxy_admin_pass = password
nova_proxy_admin_tenant_name = admin
rpc_backend = rabbit
rabbit_host = rabbitmq.openstack.svc.cluster.local
rabbit_userid = trove
rabbit_password = password
rabbit_virtual_host = trove
rabbit_port = 5672
datastore_manager = mysql

[guest_agent]
container_registry = docker.io
container_registry_username = 
container_registry_password = 

[mysql]
root_password = root-pwd
default_password_length = 36
docker_image = mysql:8.4
backup_strategy = InnoBackupEx
backup_namespace = trove.guestagent.strategies.backup.mysql_impl
restore_namespace = trove.guestagent.strategies.restore.mysql_impl
TROVE_EOF

chown trove:trove /etc/trove/trove-guestagent.conf

# Create systemd service for trove guest agent
echo "[DEBUG] Creating systemd service for trove guest agent"
date >> /tmp/debug_build_output.txt ; echo "Creating systemd service for trove guest agent" >> /tmp/debug_build_output.txt
cat > /etc/systemd/system/trove-guestagent.service << 'SERVICE_EOF'
[Unit]
Description=OpenStack Trove Guest Agent
After=network.target mysql.service cloud-init.service
Wants=mysql.service

[Service]
Type=simple
User=trove
Group=trove
ExecStart=/usr/local/venv/trove/bin/python3 /usr/local/venv/trove/bin/trove-guestagent --config-file=/etc/trove/trove-guestagent.conf
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
SERVICE_EOF

# Pre-configure MySQL root password
echo "[DEBUG] Pre-configuring MySQL root password"
date >> /tmp/debug_build_output.txt ; echo "Pre-configuring MySQL root password" >> /tmp/debug_build_output.txt
echo "mysql-server mysql-server/root_password password root-pwd" | debconf-set-selections
echo "mysql-server mysql-server/root_password_again password root-pwd" | debconf-set-selections
echo "mysql-community-server mysql-community-server/root-pass password root-pwd" | debconf-set-selections
echo "mysql-community-server mysql-community-server/re-root-pass password root-pwd" | debconf-set-selections

# Install MySQL 8.4 server
echo "[DEBUG] Installing MySQL Server 8.4"
date >> /tmp/debug_build_output.txt ; echo "Installing MySQL Server 8.4" >> /tmp/debug_build_output.txt
DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server mysql-client

# Configure MySQL for Trove
echo "[DEBUG] Configuring MySQL for Trove"
date >> /tmp/debug_build_output.txt ; echo "Configuring MySQL for Trove" >> /tmp/debug_build_output.txt
cat > /etc/mysql/mysql.conf.d/trove.cnf << 'MYSQL_EOF'
[mysqld]
# Network configuration
bind-address = 0.0.0.0
port = 3306

# Replication configuration
log-bin = mysql-bin
server-id = 1
binlog-format = ROW
gtid_mode = ON
enforce_gtid_consistency = ON

# Storage engine
default-storage-engine = InnoDB
innodb_file_per_table = 1

# Character set
collation-server = utf8mb4_unicode_ci
character-set-server = utf8mb4

# Connection limits
max_connections = 1000
max_allowed_packet = 1G
max_connect_errors = 1000000

# Performance tuning
innodb_buffer_pool_size = 1G
innodb_log_file_size = 256M
innodb_flush_log_at_trx_commit = 2
innodb_flush_method = O_DIRECT

# Logging
log_error = /var/log/mysql/error.log
slow_query_log = 1
slow_query_log_file = /var/log/mysql/slow.log
long_query_time = 2

# Security
local_infile = 0
MYSQL_EOF

# Create MySQL log directory
mkdir -p /var/log/mysql
chown mysql:mysql /var/log/mysql

# Enable services
echo "[DEBUG] Enabling services"
date >> /tmp/debug_build_output.txt ; echo "Enabling services" >> /tmp/debug_build_output.txt
systemctl daemon-reload
systemctl enable trove-guestagent
systemctl enable mysql

# Configure cloud-init for Trove
echo "[DEBUG] Configuring cloud-init for Trove"
date >> /tmp/debug_build_output.txt ; echo "Configuring cloud-init for Trove" >> /tmp/debug_build_output.txt
cat > /etc/cloud/cloud.cfg.d/99-trove.cfg << 'CLOUD_EOF'
#cloud-config
datasource_list: [ConfigDrive, OpenStack, None]
datasource:
  ConfigDrive:
    dsmode: local
  OpenStack:
    timeout: 10
    max_wait: 120
    retries: 5

# Disable automatic package updates
package_update: false
package_upgrade: false
apt_preserve_sources_list: true

disable_root: false

system_info:
  default_user:
    lock_passwd: false

# Configure users
users:
  - name: trove
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false

# Enable password authentication
ssh_pwauth: true

# Network configuration
network:
#  config: disabled
  version: 1
  config:
    - type: physical
      name: ens3
      subnets:
        - type: dhcp

# Run commands on first boot
runcmd:
  - systemctl start mysql
  - systemctl start trove-guestagent
  - echo "Trove MySQL instance started" >> /var/log/trove/startup.log
CLOUD_EOF

# Configure network to allow ping
echo "[DEBUG] Configuring network for ping"
date >> /tmp/debug_build_output.txt ; echo "Configuring network for ping" >> /tmp/debug_build_output.txt
cat > /etc/sysctl.d/99-trove-ping.conf << 'SYSCTL_EOF'
# Enable ping responses
net.ipv4.icmp_echo_ignore_all = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
SYSCTL_EOF

# Set root password for debugging
echo "[DEBUG] Setting root password"
date >> /tmp/debug_build_output.txt ; echo "Setting root password" >> /tmp/debug_build_output.txt
echo "root:root-pwd" | chpasswd

# Clean up
echo "[DEBUG] Cleaning up"
date >> /tmp/debug_build_output.txt ; echo "Cleaning up" >> /tmp/debug_build_output.txt
apt-get autoremove -y
apt-get autoclean
rm -rf /var/lib/apt/lists/*
rm -rf /var/tmp/*
rm -f /root/.bash_history
rm -f /home/trove/.bash_history 2>/dev/null || true

# Clear machine-id for cloning
date >> /tmp/debug_build_output.txt ; echo "Clearing machine-id for cloning" >> /tmp/debug_build_output.txt
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -s /etc/machine-id /var/lib/dbus/machine-id

# Clear network configuration
date >> /tmp/debug_build_output.txt ; echo "Clearing network configuration" >> /tmp/debug_build_output.txt
rm -f /etc/netplan/50-cloud-init.yaml

# Clear logs (except our debug log)
date >> /tmp/debug_build_output.txt ; echo "Clearing logs" >> /tmp/debug_build_output.txt
find /var/log -type f ! -name 'debug_build_output.txt' -exec truncate -s 0 {} \;

echo "Trove MySQL 8.4 guest image preparation completed"
date >> /tmp/debug_build_output.txt ; echo "Build complete - SSH and ping enabled" >> /tmp/debug_build_output.txt
SCRIPT_EOF

    chmod +x trove-guest-setup.sh
}

customize_image() {
    log "Customizing image with MySQL 8.4 and Trove guest agent..."
    
    # Use virt-customize to modify the image
    virt-customize -v -a "${IMAGE_NAME}-base.qcow2" \
        --run trove-guest-setup.sh \
        --selinux-relabel || error "Failed to customize image"
    
    log "Extracting build log..."
    virt-cat -a "${IMAGE_NAME}-base.qcow2" /tmp/debug_build_output.txt || warn "Could not extract build log"
}

finalize_image() {
    log "Finalizing image..."
    
    # Compress and optimize the image
    qemu-img convert -c -O qcow2 "${IMAGE_NAME}-base.qcow2" "${IMAGE_NAME}.qcow2"
    
    # Get image info
    local image_size=$(qemu-img info "${IMAGE_NAME}.qcow2" | grep "virtual size" | awk '{print $3 $4}')
    local disk_size=$(qemu-img info "${IMAGE_NAME}.qcow2" | grep "disk size" | awk '{print $3 $4}')
    
    log "Image created successfully:"
    log "  Name: ${IMAGE_NAME}.qcow2"
    log "  Virtual size: $image_size"
    log "  Disk size: $disk_size"
    log "  Location: $WORK_DIR/${IMAGE_NAME}.qcow2"
    log ""
    log "Image features:"
    log "  - MySQL 8.4 installed and configured"
    log "  - Trove guest agent installed"
    log "  - SSH access enabled"
    log "  - Ping (ICMP) enabled"
    log "  - Cloud-init configured for Trove"
}

upload_to_glance() {
    log "Uploading image to Glance..."
    
    # Check if OpenStack CLI is available and configured
    if ! command -v openstack &> /dev/null; then
        warn "OpenStack CLI not found. Please install python-openstackclient to upload to Glance"
        return 0
    fi
    
    # Check if we can connect to OpenStack
    if ! openstack token issue &> /dev/null; then
        warn "OpenStack credentials not configured. Skipping Glance upload"
        warn "To upload manually, run:"
        warn "  openstack image create --disk-format qcow2 --container-format bare --public --file $WORK_DIR/${IMAGE_NAME}.qcow2 $IMAGE_NAME"
        return 0
    fi
    
    # Upload to Glance
    openstack image create \
        --disk-format qcow2 \
        --container-format bare \
        --public \
        --property os_type=linux \
        --property os_distro=debian \
        --property os_version="12" \
        --property trove_datastore=mysql \
        --property trove_datastore_version="$MYSQL_VERSION" \
        --file "$WORK_DIR/${IMAGE_NAME}.qcow2" \
        "$IMAGE_NAME" || warn "Failed to upload to Glance"
    
    log "Image uploaded to Glance as '$IMAGE_NAME'"
}

cleanup() {
    log "Cleaning up temporary files..."
    rm -f "${IMAGE_NAME}-working-copy.qcow2"
    rm -f "${IMAGE_NAME}-base.qcow2"
    rm -f trove-guest-setup.sh
    rm -f mysql-apt-config_*.deb
}

main() {
    log "Starting MySQL 8.4 Trove image build process..."
    log "Configuration:"
    log "  Work directory: $WORK_DIR"
    log "  Image name: $IMAGE_NAME"
    log "  Image size: $IMAGE_SIZE"
    log "  MySQL version: $MYSQL_VERSION"
    log ""
    
    check_dependencies
    prepare_workspace
    download_base_image
    create_trove_guest_script
    customize_image
    finalize_image
    
    if [ "${UPLOAD_TO_GLANCE:-false}" = "true" ]; then
        upload_to_glance
    fi
    
    cleanup
    
    log ""
    log "MySQL 8.4 Trove image build completed successfully!"
    log "Image location: $WORK_DIR/${IMAGE_NAME}.qcow2"
    log ""
    log "Next steps:"
    log "  1. Upload to Glance: openstack image create --disk-format qcow2 --container-format bare --public --file $WORK_DIR/${IMAGE_NAME}.qcow2 $IMAGE_NAME"
    log "  2. Register with Trove: trove-manage datastore_version_update mysql $MYSQL_VERSION mysql <image-id> '' 1"
    log "  3. Create database instance: openstack database instance create test-db <flavor-id> --size 10 --datastore mysql --datastore-version $MYSQL_VERSION"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: sudo $0 [options]"
        echo ""
        echo "Environment variables:"
        echo "  WORK_DIR=/tmp/trove-image-build-debian  Working directory"
        echo "  IMAGE_NAME=trove-mysql-8.4-debian       Output image name"
        echo "  IMAGE_SIZE=10G                          Image size"
        echo "  MYSQL_VERSION=8.4                       MySQL version"
        echo "  UPLOAD_TO_GLANCE=false                  Upload to Glance after build"
        echo ""
        echo "Example:"
        echo "  sudo IMAGE_NAME=my-mysql-image UPLOAD_TO_GLANCE=true $0"
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac
