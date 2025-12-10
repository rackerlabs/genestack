#!/usr/bin/env bash
# shellcheck disable=SC2124,SC2145,SC2294,SC2086,SC2087,SC2155
#
# Hyperconverged Lab Deployment Selector
#
# This script provides a simple interface to deploy Genestack (OpenStack on Kubernetes)
# in a hyperconverged configuration using either:
#
#   1. Kubespray   - Traditional approach using Ubuntu VMs and Kubespray/Ansible
#   2. Talos Linux - Modern approach using Talos Linux immutable OS
#
# Usage:
#   ./hyperconverged-lab.sh                    # Interactive mode - prompts for platform
#   ./hyperconverged-lab.sh kubespray [args]   # Deploy using Kubespray
#   ./hyperconverged-lab.sh talos [args]       # Deploy using Talos Linux
#
# For uninstall, use the corresponding uninstall scripts:
#   ./hyperconverged-lab-kubespray-uninstall.sh
#   ./hyperconverged-lab-talos-uninstall.sh
#

set -o pipefail
set -e
SECONDS=0
RUN_EXTRAS=0
INCLUDE_LIST=()
EXCLUDE_LIST=()

export TEST_LEVEL="${TEST_LEVEL:-off}"

# yq installation constants
YQ_VERSION="v4.2.0"
YQ_BINARY="yq_linux_amd64"

function installYq() {
    if wget https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${YQ_BINARY}.tar.gz -O - | tar xz && sudo mv ${YQ_BINARY} /usr/local/bin/yq; then
        echo "Successfully installed yq version ${YQ_VERSION}"
        return 0
    else
        echo "Failed to install yq"
        return 1
    fi
}

# Install yq locally if needed...
if ! yq --version 2> /dev/null; then
  echo "yq is not installed. Attempting to install yq"
  if ! installYq; then
    echo "[WARNING] Failed to install yq locally"
  fi
fi


# Default openstack components file
# this controls which openstack service will be installed
##...needed until default config is upstream...
OS_CONFIG="
components:
  keystone: true
  glance: true
  heat: false
  barbican: false
  blazar: false
  cloudkitty: false
  cinder: true
  freezer: false
  placement: true
  nova: true
  neutron: true
  magnum: false
  octavia: false
  masakari: false
  manila: false
  ceilometer: false
  gnocchi: false
  skyline: true
  zaqar: false
"
echo -e "$OS_CONFIG" > $PWD/openstack-components.yaml

while getopts "i:e:x" opt; do
  case $opt in
    x)
      RUN_EXTRAS=1
      ;;
    i)
      old_IFS="$IFS"
      IFS=','
      read -r -a INCLUDE_LIST <<< "$OPTARG"
      IFS="$old_IFS"
      ;;
    e)
      old_IFS="$IFS"
      IFS=','
      read -r -a EXCLUDE_LIST <<< "$OPTARG"
      IFS="$old_IFS"
      ;;
    *)
      echo "Usage: $0 [-i <list,of,services,to,include>]
      [-e <ist,of,services,to,exclude>]
      -x <flag only will run extra operations>\n"
      echo "View the openstack-components.yaml for the services available to configure."
      exit 1
      ;;
    \?) # Handle invalid options
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
  esac
done
shift $((OPTIND-1))

for option in "${INCLUDE_LIST[@]}"; do
  yq -i ".components.$option = true" $PWD/openstack-components.yaml
done
for option in "${EXCLUDE_LIST[@]}"; do
    yq -i ".components.$option = false" $PWD/openstack-components.yaml
done

if [ -z "${ACME_EMAIL}" ]; then
  read -rp "Enter a valid email address for use with ACME, press enter to skip: " ACME_EMAIL
fi

# Use of ACME_EMAIL to default Email
ACME_EMAIL="${ACME_EMAIL:-example@aol.com}"
export ACME_EMAIL

if [ -z "${GATEWAY_DOMAIN}" ]; then
  echo "The domain name for the gateway is required, if you do not have a domain name press enter to use the default"
  read -rp "Enter the domain name for the gateway [cluster.local]: " GATEWAY_DOMAIN
  export GATEWAY_DOMAIN="${GATEWAY_DOMAIN:-cluster.local}"
fi

if [ -z "${OS_CLOUD}" ]; then
  read -rp "Enter name of the cloud configuration used for this build [default]: " OS_CLOUD
  export OS_CLOUD="${OS_CLOUD:-default}"
fi

if [ -z "${OS_FLAVOR}" ]; then
  # List compatible flavors
  FLAVORS=$(openstack flavor list --min-ram 16000 --min-disk 100 --sort-column Name -c Name -c RAM -c Disk -c VCPUs -f json)
  DEFAULT_OS_FLAVOR=$(echo "${FLAVORS}" | jq -r '[.[] | select( all(.RAM; . < 24576) )] | .[0].Name')
  echo "The following flavors are available for use with this build"
  echo "${FLAVORS}" | jq -r '["Name", "RAM", "Disk", "VCPUs"], (.[] | [.Name, .RAM, .Disk, .VCPUs]) | @tsv' | column -t
  read -rp "Enter name of the flavor to use for the instances [${DEFAULT_OS_FLAVOR}]: " OS_FLAVOR
  export OS_FLAVOR=${OS_FLAVOR:-${DEFAULT_OS_FLAVOR}}
fi

# Set the default image and ssh username
export OS_IMAGE="${OS_IMAGE:-Ubuntu 24.04}"
if [ -z "${SSH_USERNAME}" ]; then
  if ! IMAGE_DEFAULT_PROPERTY=$(openstack image show "${OS_IMAGE}" -f json -c properties); then
    read -rp "Image not found. Enter the image name: " OS_IMAGE
    IMAGE_DEFAULT_PROPERTY=$(openstack image show "${OS_IMAGE}" -f json -c properties)
  fi
  if [ "${IMAGE_DEFAULT_PROPERTY}" ]; then
    if SSH_USERNAME=$(echo "${IMAGE_DEFAULT_PROPERTY}" | jq -r '.properties.default_user'); then
      echo "Discovered the default username for the image ${OS_IMAGE} as ${SSH_USERNAME}"
    fi
  fi
  if [ -z "${SSH_USERNAME}" ] || [ "${SSH_USERNAME}" = "null" ]; then
    echo "The image ${OS_IMAGE} does not have a default user property, please enter the default username"
    read -rp "Enter the default username for the image: " SSH_USERNAME
  fi
fi

export LAB_NAME_PREFIX="${LAB_NAME_PREFIX:-hyperconverged}"

export LAB_NETWORK_MTU="${LAB_NETWORK_MTU:-1500}"

if ! openstack router show ${LAB_NAME_PREFIX}-router 2>/dev/null; then
  openstack router create ${LAB_NAME_PREFIX}-router --external-gateway PUBLICNET
fi

if ! openstack network show ${LAB_NAME_PREFIX}-net 2>/dev/null; then
  openstack network create ${LAB_NAME_PREFIX}-net \
    --mtu ${LAB_NETWORK_MTU}
fi

if ! TENANT_SUB_NETWORK_ID=$(openstack subnet show ${LAB_NAME_PREFIX}-subnet -f json 2>/dev/null | jq -r '.id'); then
  echo "Creating the ${LAB_NAME_PREFIX}-subnet"
  TENANT_SUB_NETWORK_ID=$(
    openstack subnet create ${LAB_NAME_PREFIX}-subnet \
      --network ${LAB_NAME_PREFIX}-net \
      --subnet-range 192.168.100.0/24 \
      --dns-nameserver 1.1.1.1 \
      --dns-nameserver 1.0.0.1 \
      -f json | jq -r '.id'
  )
fi

if ! openstack router show ${LAB_NAME_PREFIX}-router -f json 2>/dev/null | jq -r '.interfaces_info.[].subnet_id' | grep -q ${TENANT_SUB_NETWORK_ID}; then
  openstack router add subnet ${LAB_NAME_PREFIX}-router ${LAB_NAME_PREFIX}-subnet
fi

if ! openstack network show ${LAB_NAME_PREFIX}-compute-net 2>/dev/null; then
  openstack network create ${LAB_NAME_PREFIX}-compute-net \
    --disable-port-security \
    --mtu ${LAB_NETWORK_MTU}
fi

if ! TENANT_COMPUTE_SUB_NETWORK_ID=$(openstack subnet show ${LAB_NAME_PREFIX}-compute-subnet -f json 2>/dev/null | jq -r '.id'); then
  echo "Creating the ${LAB_NAME_PREFIX}-compute-subnet"
  TENANT_COMPUTE_SUB_NETWORK_ID=$(
    openstack subnet create ${LAB_NAME_PREFIX}-compute-subnet \
      --network ${LAB_NAME_PREFIX}-compute-net \
      --subnet-range 192.168.102.0/24 \
      --no-dhcp -f json | jq -r '.id'
  )
fi

if ! openstack router show ${LAB_NAME_PREFIX}-router -f json | jq -r '.interfaces_info.[].subnet_id' | grep -q ${TENANT_COMPUTE_SUB_NETWORK_ID} 2>/dev/null; then
  openstack router add subnet ${LAB_NAME_PREFIX}-router ${LAB_NAME_PREFIX}-compute-subnet
fi

if ! openstack security group show ${LAB_NAME_PREFIX}-http-secgroup 2>/dev/null; then
  openstack security group create ${LAB_NAME_PREFIX}-http-secgroup
fi

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

function show_usage() {
    cat <<EOF
Hyperconverged Lab Deployment Script

This script deploys Genestack (OpenStack on Kubernetes) in a hyperconverged
configuration on OpenStack infrastructure.

USAGE:
    $(basename "$0") [PLATFORM] [OPTIONS]

PLATFORMS:
    kubespray    Deploy using Kubespray on Ubuntu (traditional approach)
                 - Uses Ubuntu VMs with SSH access
                 - Kubernetes deployed via Kubespray/Ansible
                 - Requires SSH keypair for node access

    talos        Deploy using Talos Linux (modern approach)
                 - Uses Talos Linux immutable OS
                 - Kubernetes deployed via talosctl
                 - No SSH - managed via Talos API
                 - Includes Talos-specific configs for Longhorn, Kube-OVN, Ceph

    help         Show this help message

OPTIONS:
    -i <list>    Comma-separated list of OpenStack services to include
    -e <list>    Comma-separated list of OpenStack services to exclude
    -x           Run extra operations (k9s install, Octavia preconf, etc.)

ENVIRONMENT VARIABLES:
    ACME_EMAIL          Email for ACME/Let's Encrypt certificates
    GATEWAY_DOMAIN      Domain name for the gateway (default: cluster.local)
    OS_CLOUD            OpenStack cloud configuration name (default: default)
    OS_FLAVOR           Flavor to use for instances
    OS_IMAGE            Image to use (platform-specific defaults apply)
    LAB_NAME_PREFIX     Prefix for all created resources
    LAB_NETWORK_MTU     MTU for lab networks (default: 1500)
    HYPERCONVERGED_DEV  If set to "true", enables development mode which transports
                        the local environment checkout into the hyperconverged lab
                        for easier testing and debugging.

EXAMPLES:
    # Interactive mode - will prompt for platform choice
    $(basename "$0")

    # Deploy using Kubespray
    $(basename "$0") kubespray

    # Deploy using Talos Linux
    $(basename "$0") talos

    # Deploy Kubespray with extra services and extras enabled
    $(basename "$0") kubespray -i heat,octavia -x

    # Deploy Talos with specific services excluded
    $(basename "$0") talos -e skyline

# Install yq on the remote host if not already present
if ! command -v yq &> /dev/null; then
  echo "Installing yq on remote host..."
  if wget https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${YQ_BINARY}.tar.gz -O - | tar xz && sudo mv ${YQ_BINARY} /usr/local/bin/yq; then
    echo "Successfully installed yq version ${YQ_VERSION} on remote host"
  else
    echo "Failed to install yq on remote host"
    exit 1
  fi
else
  echo "yq already available on remote host: \$(yq --version)"
fi

# We need to clobber the sample or else we get a bogus LB vip
cat > /etc/genestack/manifests/metallb/metallb-openstack-service-lb.yml <<EOF
---
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: gateway-api-external
  namespace: metallb-system
spec:
  addresses:
    - ${METAL_LB_IP}/32  # This is assumed to be the public LB vip address
  autoAssign: false
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: openstack-external-advertisement
  namespace: metallb-system
spec:
  ipAddressPools:
    - gateway-api-external
EOF

UNINSTALL:
    Use the platform-specific uninstall scripts:

    # Uninstall Kubespray deployment
    ./hyperconverged-lab-kubespray-uninstall.sh

    # Uninstall Talos deployment
    ./hyperconverged-lab-talos-uninstall.sh

For more information, see the Genestack documentation.
EOF

fi
EOC

# Run host and K8S setup
ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t ${SSH_USERNAME}@${JUMP_HOST_VIP} <<EOC
set -e
if [ ! -f "/usr/local/bin/queue_max.sh" ]; then
  python3 -m venv ~/.venvs/genestack
  ~/.venvs/genestack/bin/pip install -r /opt/genestack/requirements.txt
  source /opt/genestack/scripts/genestack.rc
  ANSIBLE_SSH_PIPELINING=0 ansible-playbook /opt/genestack/ansible/playbooks/host-setup.yml --become -e host_required_kernel=\$(uname -r)
fi
if [ ! -d "/var/lib/kubelet" ]; then
  source /opt/genestack/scripts/genestack.rc
  cd /opt/genestack/submodules/kubespray
  ANSIBLE_SSH_PIPELINING=0 ansible-playbook cluster.yml --become
fi
sudo mkdir -p /opt/kube-plugins
sudo chown \${USER}:\${USER} /opt/kube-plugins
pushd /opt/kube-plugins
  if [ ! -f "/usr/local/bin/kubectl" ]; then
    curl -LO "https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  fi
  if [ ! -f "/usr/local/bin/kubectl-convert" ]; then
    curl -LO "https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl-convert"
    sudo install -o root -g root -m 0755 kubectl-convert /usr/local/bin/kubectl-convert
  fi
  if [ ! -f "/usr/local/bin/kubectl-ko" ]; then
    curl -LO https://raw.githubusercontent.com/kubeovn/kube-ovn/refs/heads/release-1.12/dist/images/kubectl-ko
    sudo install -o root -g root -m 0755 kubectl-ko /usr/local/bin/kubectl-ko
  fi
popd
EOC

echo "Creating config for setup-openstack.sh"
ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t ${SSH_USERNAME}@${JUMP_HOST_VIP} <<EOC
set -e
if [ ! -f "/etc/genestack/openstack-components.yaml" ]; then
  echo -e "$OS_CONFIG" > /etc/genestack/openstack-components.yaml
fi
EOC

# Run Genestack Infrastucture/OpenStack Setup
ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t ${SSH_USERNAME}@${JUMP_HOST_VIP} <<EOC
set -e
echo "Installing OpenStack Infrastructure"
sudo LONGHORN_STORAGE_REPLICAS=1 \
     GATEWAY_DOMAIN="${GATEWAY_DOMAIN}" \
     ACME_EMAIL="${ACME_EMAIL}" \
     HYPERCONVERGED=true \
     /opt/genestack/bin/setup-infrastructure.sh
echo "Installing OpenStack"
sudo /opt/genestack/bin/setup-openstack.sh
EOC

# Run Genestack post setup
ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t ${SSH_USERNAME}@${JUMP_HOST_VIP} <<EOC
set -e
sudo bash <<HERE
sudo /opt/genestack/bin/setup-openstack-rc.sh
source /opt/genestack/scripts/genestack.rc

# Function to retry openstack commands with backoff
retry_openstack_command() {
  local cmd="\\\$1"
  local description="\\\$2"
  local retry_count=0
  local max_retries=12  # 12 retries * 10 seconds = 2 minutes

  while [ \\\$retry_count -lt \\\$max_retries ]; do
    echo "Attempting: \\\$description"
    if eval "\\\$cmd"; then
      echo "\\\$description succeeded"
      return 0
    else
      retry_count=\\\$((retry_count + 1))
      echo "\\\$description failed (attempt \\\$retry_count/\\\$max_retries). Retrying in 10 seconds..."
      if [ \\\$retry_count -eq \\\$max_retries ]; then
        echo "\\\$description failed after \\\$max_retries attempts. Continuing anyway..."
        return 1
      fi
      sleep 10
    fi
  done
}

# Create flavor with retry
retry_openstack_command "if ! openstack --os-cloud default flavor show ${LAB_NAME_PREFIX}-test; then openstack --os-cloud default flavor create ${LAB_NAME_PREFIX}-test --public --ram 2048 --disk 10 --vcpus 2; fi" "Flavor setup"

# Create network with retry
retry_openstack_command "if ! openstack --os-cloud default network show flat; then openstack --os-cloud default network create --share --availability-zone-hint az1 --external --provider-network-type flat --provider-physical-network physnet1 flat; fi" "Network setup"

# Create subnet with retry
retry_openstack_command "if ! openstack --os-cloud default subnet show flat_subnet; then openstack --os-cloud default subnet create --subnet-range 192.168.102.0/24 --gateway 192.168.102.1 --dns-nameserver 1.1.1.1 --allocation-pool start=192.168.102.100,end=192.168.102.109 --dhcp --network flat flat_subnet; fi" "Subnet setup"
HERE
EOC

# Extra operations...
install_k9s() {
echo "Installing k9s"
ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t ${SSH_USERNAME}@${JUMP_HOST_VIP} << 'EOC'
set -e
echo "Installing k9s"
if [ ! -e "/usr/bin/k9s" ]; then
  sudo wget https://github.com/derailed/k9s/releases/latest/download/k9s_linux_amd64.deb && mv ./k9s_linux_amd64.deb /tmp/ && sudo apt install /tmp/k9s_linux_amd64.deb && sudo rm /tmp/k9s_linux_amd64.deb
fi

if [ ! -d ~/.kube ]; then
  mkdir ~/.kube
  sudo cp -i /etc/kubernetes/admin.conf ~/.kube/config
  sudo chown $(id -u):$(id -g) ~/.kube/config
fi
EOC

}

function prompt_for_platform() {
    echo ""
    echo "Hyperconverged Lab Deployment"
    echo "============================="
    echo ""
    echo "Select your deployment platform:"
    echo ""
    echo "  1) Kubespray"
    echo "     - Traditional approach using Ubuntu VMs"
    echo "     - Kubernetes deployed via Kubespray/Ansible"
    echo "     - SSH-based node management"
    echo ""
    echo "  2) Talos Linux"
    echo "     - Modern immutable Linux OS designed for Kubernetes"
    echo "     - API-based management (no SSH)"
    echo "     - Includes Talos-specific configurations for Longhorn, Kube-OVN, Ceph"
    echo ""

    read -rp "Enter your choice [1/2]: " choice

    case "$choice" in
        1|kubespray|Kubespray|KUBESPRAY)
            echo ""
            echo "Selected: Kubespray"
            PLATFORM="kubespray"
            ;;
        2|talos|Talos|TALOS)
            echo ""
            echo "Selected: Talos Linux"
            PLATFORM="talos"
            ;;
        *)
            echo "Invalid choice. Please enter 1 or 2."
            exit 1
            ;;
    esac
}

# Check for help flag first
if [[ "$1" == "help" || "$1" == "--help" || "$1" == "-h" ]]; then
    show_usage
    exit 0
fi

# Determine platform from first argument or prompt
if [[ -n "$1" && "$1" != -* ]]; then
    case "$1" in
        kubespray|Kubespray|KUBESPRAY)
            PLATFORM="kubespray"
            shift
            ;;
        talos|Talos|TALOS)
            PLATFORM="talos"
            shift
            ;;
        *)
            echo "Unknown platform: $1"
            echo ""
            show_usage
            exit 1
            ;;
    esac
else
    prompt_for_platform
fi

# Execute the appropriate platform-specific script
case "$PLATFORM" in
    kubespray)
        echo ""
        echo "Launching Kubespray deployment..."
        echo ""
        exec "${SCRIPT_DIR}/hyperconverged-lab-kubespray.sh" "$@"
        ;;
    talos)
        echo ""
        echo "Launching Talos Linux deployment..."
        echo ""
        exec "${SCRIPT_DIR}/hyperconverged-lab-talos.sh" "$@"
        ;;
esac
