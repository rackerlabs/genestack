#!/usr/bin/env bash
# shellcheck disable=SC2124,SC2145,SC2294,SC2086,SC2087,SC2155
#
# Hyperconverged Lab Common Library
#
# This library contains shared functions and configurations used by both
# Kubespray and Talos Linux hyperconverged lab deployments.
#
# Source this file from platform-specific scripts:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/hyperconverged-common.sh"
#

#############################################################################
# Common Variables and Defaults
#############################################################################

export TEST_LEVEL="${TEST_LEVEL:-off}"
export LAB_NETWORK_MTU="${LAB_NETWORK_MTU:-1500}"

#############################################################################
# Common Utility Functions
#############################################################################

# Source common functions (installYq, ensureYq)
# Note: hyperconverged scripts run from a workstation, so we use a relative path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/functions.sh"

function parseCommonArgs() {
    # Parse common command line arguments
    # Usage: parseCommonArgs "$@"
    # Sets: RUN_EXTRAS, INCLUDE_LIST, EXCLUDE_LIST

    RUN_EXTRAS=0

    if [ "${HYPERCONVERGED_CINDER_VOLUME:-false}" = "true" ]; then
        # barbican is needed for iSCSI encrypted volumes and cinder install has to be
        #  done much later during the cinder volume setup
        INCLUDE_LIST=("keystone" "barbican" "glance" "nova" "neutron" "placement")
        EXCLUDE_LIST=("cinder")
    else
        INCLUDE_LIST=("keystone" "glance" "cinder" "nova" "neutron" "placement")
        EXCLUDE_LIST=()
    fi

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
                echo "Usage: $0 [-i <list,of,services,to,include>]"
                echo "       [-e <list,of,services,to,exclude>]"
                echo "       -x <flag to run extra operations>"
                echo ""
                echo "View the openstack-components.yaml for the services available to configure."
                exit 1
                ;;
            \?)
                echo "Invalid option: -$OPTARG" >&2
                exit 1
                ;;
        esac
    done
    shift $((OPTIND-1))

    export RUN_EXTRAS
    export INCLUDE_LIST
    export EXCLUDE_LIST
}

function writeOpenstackComponentsConfig() {
    # Write OpenStack components configuration file
    # Usage: writeOpenstackComponentsConfig [output_path]
    local output_path="${1:-/tmp/openstack-components.yaml}"
    local os_config="${2}"

    echo "Writing OpenStack components configuration to ${output_path}"

    INCLUDE_LIST=($INCLUDE_LIST)
    EXCLUDE_LIST=($EXCLUDE_LIST)

    echo -e "${os_config}" | tee "${output_path}"

    for option in "${INCLUDE_LIST[@]}"; do
        echo "include option: ${option}"
        yq -i ".components.$option = true" "${output_path}"
    done
    for option in "${EXCLUDE_LIST[@]}"; do
        echo "exclude option: ${option}"
        yq -i ".components.$option = false" "${output_path}"
    done
    cat ${output_path}
}

function promptForCommonInputs() {
    # Prompt for common user inputs (ACME_EMAIL, GATEWAY_DOMAIN, OS_CLOUD, OS_FLAVOR)

    if [ -z "${ACME_EMAIL}" ]; then
        read -rp "Enter a valid email address for use with ACME, press enter to skip: " ACME_EMAIL
    fi
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
}

#############################################################################
# OpenStack Infrastructure Functions
#############################################################################

function createRouter() {
    # Create router with external gateway
    if ! openstack router show ${LAB_NAME_PREFIX}-router 2>/dev/null; then
        openstack router create ${LAB_NAME_PREFIX}-router --external-gateway PUBLICNET
    fi
}

function createNetworks() {
    # Create management network
    if ! openstack network show ${LAB_NAME_PREFIX}-net 2>/dev/null; then
        openstack network create ${LAB_NAME_PREFIX}-net \
            --mtu ${LAB_NETWORK_MTU}
    fi

    # Create management subnet
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
    export TENANT_SUB_NETWORK_ID

    # Add subnet to router
    if ! openstack router show ${LAB_NAME_PREFIX}-router -f json 2>/dev/null | jq -r '.interfaces_info[].subnet_id' | grep -q ${TENANT_SUB_NETWORK_ID}; then
        openstack router add subnet ${LAB_NAME_PREFIX}-router ${LAB_NAME_PREFIX}-subnet
    fi

    # Create compute network (no port security for flat provider network)
    if ! openstack network show ${LAB_NAME_PREFIX}-compute-net 2>/dev/null; then
        openstack network create ${LAB_NAME_PREFIX}-compute-net \
            --disable-port-security \
            --mtu ${LAB_NETWORK_MTU}
    fi

    # Create compute subnet (no DHCP)
    if ! TENANT_COMPUTE_SUB_NETWORK_ID=$(openstack subnet show ${LAB_NAME_PREFIX}-compute-subnet -f json 2>/dev/null | jq -r '.id'); then
        echo "Creating the ${LAB_NAME_PREFIX}-compute-subnet"
        TENANT_COMPUTE_SUB_NETWORK_ID=$(
            openstack subnet create ${LAB_NAME_PREFIX}-compute-subnet \
                --network ${LAB_NAME_PREFIX}-compute-net \
                --subnet-range 192.168.102.0/24 \
                --no-dhcp -f json | jq -r '.id'
        )
    fi
    export TENANT_COMPUTE_SUB_NETWORK_ID

    # Add compute subnet to router
    if ! openstack router show ${LAB_NAME_PREFIX}-router -f json | jq -r '.interfaces_info[].subnet_id' | grep -q ${TENANT_COMPUTE_SUB_NETWORK_ID} 2>/dev/null; then
        openstack router add subnet ${LAB_NAME_PREFIX}-router ${LAB_NAME_PREFIX}-compute-subnet
    fi
}

function createCommonSecurityGroups() {
    # Create HTTP/HTTPS security group
    if ! openstack security group show ${LAB_NAME_PREFIX}-http-secgroup 2>/dev/null; then
        openstack security group create ${LAB_NAME_PREFIX}-http-secgroup
    fi

    if ! openstack security group show ${LAB_NAME_PREFIX}-http-secgroup -f json 2>/dev/null | jq -r '.rules[].port_range_max' | grep -q 443; then
        openstack security group rule create ${LAB_NAME_PREFIX}-http-secgroup \
            --protocol tcp \
            --ingress \
            --remote-ip 0.0.0.0/0 \
            --dst-port 443 \
            --description "https"
    fi
    if ! openstack security group show ${LAB_NAME_PREFIX}-http-secgroup -f json 2>/dev/null | jq -r '.rules[].port_range_max' | grep -q 80; then
        openstack security group rule create ${LAB_NAME_PREFIX}-http-secgroup \
            --protocol tcp \
            --ingress \
            --remote-ip 0.0.0.0/0 \
            --dst-port 80 \
            --description "http"
    fi

    # Create internal traffic security group
    if ! openstack security group show ${LAB_NAME_PREFIX}-secgroup 2>/dev/null; then
        openstack security group create ${LAB_NAME_PREFIX}-secgroup
    fi

    if ! openstack security group show ${LAB_NAME_PREFIX}-secgroup -f json 2>/dev/null | jq -r '.rules[].description' | grep -q "all internal traffic"; then
        openstack security group rule create ${LAB_NAME_PREFIX}-secgroup \
            --protocol any \
            --ingress \
            --remote-ip 192.168.100.0/24 \
            --description "all internal traffic"
    fi
}

function createMetalLBPort() {
    # Create MetalLB VIP port and floating IP
    if ! METAL_LB_IP=$(openstack port show ${LAB_NAME_PREFIX}-metallb-vip-0-port -f json 2>/dev/null | jq -r '.fixed_ips[0].ip_address'); then
        echo "Creating the MetalLB VIP port"
        METAL_LB_IP=$(openstack port create --security-group ${LAB_NAME_PREFIX}-http-secgroup --network ${LAB_NAME_PREFIX}-net ${LAB_NAME_PREFIX}-metallb-vip-0-port -f json | jq -r '.fixed_ips[0].ip_address')
    fi
    export METAL_LB_IP

    METAL_LB_PORT_ID=$(openstack port show ${LAB_NAME_PREFIX}-metallb-vip-0-port -f value -c id)
    export METAL_LB_PORT_ID

    if ! METAL_LB_VIP=$(openstack floating ip list --port ${METAL_LB_PORT_ID} -f json 2>/dev/null | jq -r '.[]."Floating IP Address"'); then
        echo "Creating the MetalLB VIP floating IP"
        METAL_LB_VIP=$(openstack floating ip create PUBLICNET --port ${METAL_LB_PORT_ID} -f json | jq -r '.floating_ip_address')
    elif [ -z "${METAL_LB_VIP}" ]; then
        METAL_LB_VIP=$(openstack floating ip create PUBLICNET --port ${METAL_LB_PORT_ID} -f json | jq -r '.floating_ip_address')
    fi
    export METAL_LB_VIP
}

function createComputePorts() {
    # Create compute network ports for flat test network
    echo "Creating pre-defined compute ports for the flat test network"
    for i in {100..109}; do
        if ! openstack port show ${LAB_NAME_PREFIX}-0-compute-float-${i}-port 2>/dev/null; then
            openstack port create --network ${LAB_NAME_PREFIX}-compute-net \
                --disable-port-security \
                --fixed-ip ip-address="192.168.102.${i}" \
                ${LAB_NAME_PREFIX}-0-compute-float-${i}-port
        fi
    done

    # Create compute ports for each node
    if ! COMPUTE_0_PORT=$(openstack port show ${LAB_NAME_PREFIX}-0-compute-port -f value -c id 2>/dev/null); then
        export COMPUTE_0_PORT=$(
            openstack port create --network ${LAB_NAME_PREFIX}-compute-net \
                --no-fixed-ip \
                --disable-port-security \
                -f value \
                -c id \
                ${LAB_NAME_PREFIX}-0-compute-port
        )
    fi
    export COMPUTE_0_PORT

    if ! COMPUTE_1_PORT=$(openstack port show ${LAB_NAME_PREFIX}-1-compute-port -f value -c id 2>/dev/null); then
        export COMPUTE_1_PORT=$(
            openstack port create --network ${LAB_NAME_PREFIX}-compute-net \
                --no-fixed-ip \
                --disable-port-security \
                -f value \
                -c id \
                ${LAB_NAME_PREFIX}-1-compute-port
        )
    fi
    export COMPUTE_1_PORT

    if ! COMPUTE_2_PORT=$(openstack port show ${LAB_NAME_PREFIX}-2-compute-port -f value -c id 2>/dev/null); then
        export COMPUTE_2_PORT=$(
            openstack port create --network ${LAB_NAME_PREFIX}-compute-net \
                --no-fixed-ip \
                --disable-port-security \
                -f value \
                -c id \
                ${LAB_NAME_PREFIX}-2-compute-port
        )
    fi
    export COMPUTE_2_PORT
}

#############################################################################
# Genestack Configuration Functions
#############################################################################

function prepareJumpHostSource() {
    # Prepare the jump host with the Genestack source code
    # Usage: cloneGenestackOnJumpHost

    local DEV_PATH="$(readlink -fn ${SCRIPT_DIR}/../../)"

    if [ "${HYPERCONVERGED_DEV:-false}" = "true" ]; then
        if [ ! -d "${DEV_PATH}" ]; then
            echo "HYPERCONVERGED_DEV is true, but we've failed to determine the base genestack directory"
            exit 1
        fi
        # NOTE: we are assuming an Ubuntu (apt) based instance here
        ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t ${SSH_USERNAME}@${JUMP_HOST_VIP} \
            "while sudo fuser /var/{lib/{dpkg,apt/lists},cache/apt/archives}/lock >/dev/null 2>&1; do echo 'Waiting for apt locks to be released...'; sleep 5; done && sudo apt-get update && sudo apt install -y rsync git"
        echo "Copying the development source code to the jump host"
        rsync -avz \
            -e "ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no" \
            --rsync-path="sudo rsync" --chown=":ubuntu" \
            ${DEV_PATH} ${SSH_USERNAME}@${JUMP_HOST_VIP}:/opt/
    else
        cloneGenestackOnJumpHost
    fi
}

function writeMetalLBConfig() {
    # Write MetalLB configuration
    # Usage: writeMetalLBConfig <metal_lb_ip> [config_path]
    local metal_lb_ip="$1"
    local config_path="${2:-/etc/genestack/manifests/metallb/metallb-openstack-service-lb.yml}"

    cat > "${config_path}" <<EOF
---
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: gateway-api-external
  namespace: metallb-system
spec:
  addresses:
    - ${metal_lb_ip}/32
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
}

function writeServiceHelmOverrides() {
    # Write all OpenStack service Helm overrides for lab environment
    # These are minimal resource configurations suitable for lab deployments

    local config_base="${1:-/etc/genestack/helm-configs}"

    if [ ! -f "${config_base}/envoyproxy-gateway/envoyproxy-gateway-helm-overrides.yaml" ]; then
        cat > "${config_base}/envoyproxy-gateway/envoyproxy-gateway-helm-overrides.yaml" <<EOF
---
EOF
    fi

    if [ ! -f "${config_base}/barbican/barbican-helm-overrides.yaml" ]; then
        if [ "${HYPERCONVERGED_CINDER_VOLUME:-false}" = "true" ]; then
            cat > "${config_base}/barbican/barbican-helm-overrides.yaml" <<EOF
---
pod:
  resources:
    enabled: false

conf:
  barbican_api_uwsgi:
    uwsgi:
      processes: 4
  barbican:
    oslo_messaging_notifications:
      driver: noop
EOF
        else
            cat > "${config_base}/barbican/barbican-helm-overrides.yaml" <<EOF
---
pod:
  resources:
    enabled: false

conf:
  barbican_api_uwsgi:
    uwsgi:
      processes: 1
  barbican:
    oslo_messaging_notifications:
      driver: noop
EOF
        fi
    fi

    if [ ! -f "${config_base}/blazar/blazar-helm-overrides.yaml" ]; then
        cat > "${config_base}/blazar/blazar-helm-overrides.yaml" <<EOF
---
pod:
  resources:
    enabled: false

conf:
  blazar_api_uwsgi:
    uwsgi:
      processes: 1
  blazar:
    oslo_messaging_notifications:
      driver: noop
EOF
    fi

    if [ ! -f "${config_base}/cinder/cinder-helm-overrides.yaml" ]; then
        if [ "${HYPERCONVERGED_CINDER_VOLUME:-false}" = "true" ]; then
            cat > "${config_base}/cinder/cinder-helm-overrides.yaml" <<EOF
---
images:
  tags:
    bootstrap: "ghcr.io/rackerlabs/genestack-images/heat:2024.1-1754784075"
    cinder_api: "ghcr.io/rackerlabs/genestack-images/cinder:2024.1-1754785862"
    cinder_backup: "ghcr.io/rackerlabs/genestack-images/cinder:2024.1-1754785862"
    cinder_backup_storage_init: "quay.io/rackspace/rackerlabs-ceph-config-helper:latest-ubuntu_jammy"
    cinder_db_sync: "ghcr.io/rackerlabs/genestack-images/cinder:2024.1-1754785862"
    cinder_scheduler: "ghcr.io/rackerlabs/genestack-images/cinder:2024.1-1754785862"
    cinder_storage_init: "quay.io/rackspace/rackerlabs-ceph-config-helper:latest-ubuntu_jammy"
    cinder_volume: "ghcr.io/rackerlabs/genestack-images/cinder:2024.1-1754785862"
    cinder_volume_usage_audit: "ghcr.io/rackerlabs/genestack-images/cinder:2024.1-1754785862"
    db_drop: "ghcr.io/rackerlabs/genestack-images/heat:2024.1-1754784075"
    db_init: "ghcr.io/rackerlabs/genestack-images/heat:2024.1-1754784075"
    dep_check: "ghcr.io/rackerlabs/genestack-images/kubernetes-entrypoint:latest"
    ks_endpoints: "ghcr.io/rackerlabs/genestack-images/heat:2024.1-1754784075"
    ks_service: "ghcr.io/rackerlabs/genestack-images/heat:2024.1-1754784075"
    ks_user: "ghcr.io/rackerlabs/genestack-images/heat:2024.1-1754784075"
pod:
  resources:
    enabled: true
    api:
      requests:
        cpu: "1"
        memory: "1Gi"
      limits:
        cpu: "2"
        memory: "2Gi"
    scheduler:
      requests:
        cpu: "1"
        memory: "1Gi"
      limits:
        cpu: "2"
        memory: "2Gi"
conf:
# NOTE: (brew) uncomment to change default log level from INFO
#  logging:
#    logger_cinder:
#      level: DEBUG
#      handlers: stdout
  policy:
    "volume_extension:types_extra_specs:read_sensitive": "rule:xena_system_admin_or_project_reader"
  cinder:
    DEFAULT:
      osapi_volume_workers: 2
      rpc_response_timeout: 300
      enabled_backends: "lvmdriver-1"
      default_volume_type: "Standard"
      default_availability_zone: "az1"
  backends:
    lvmdriver-1:
      image_volume_cache_enabled: true
      iscsi_iotype: fileio
      iscsi_num_targets: 100
      lvm_type: default
      target_helper: tgtadm
      target_port: 3260
      target_protocol: iscsi
      volume_backend_name: LVM_iSCSI
      volume_clear: zero
      volume_driver: cinder_rxt.rackspace.RXTLVM
      volume_group: cinder-volumes-1
      volume_clear_size: 128
  cinder_api_uwsgi:
    uwsgi:
      processes: 2
      threads: 1
EOF
        else
            cat > "${config_base}/cinder/cinder-helm-overrides.yaml" <<EOF
---
pod:
  resources:
    enabled: false
conf:
  cinder:
    DEFAULT:
      osapi_volume_workers: 1
    oslo_messaging_notifications:
      driver: noop
  cinder_api_uwsgi:
    uwsgi:
      processes: 1
      threads: 1
EOF
        fi
    fi

    if [ ! -f "${config_base}/trove/trove-helm-overrides.yaml" ]; then
        cat > "${config_base}/trove/trove-helm-overrides.yaml" <<EOF
---
pod:
  resources:
    enabled: false
conf:
  trove:
    DEFAULT:
      trove_api_workers: 1
      management_networks:
      management_security_groups:
    oslo_messaging_notifications:
      driver: noop
  trove_api_uwsgi:
    uwsgi:
      processes: 1
      threads: 1
EOF
    fi

    if [ ! -f "${config_base}/glance/glance-helm-overrides.yaml" ]; then
        cat > "${config_base}/glance/glance-helm-overrides.yaml" <<EOF
---
pod:
  resources:
    enabled: false
conf:
  glance:
    DEFAULT:
      workers: 2
    oslo_messaging_notifications:
      driver: noop
  glance_api_uwsgi:
    uwsgi:
      processes: 1
volume:
  class_name: general
  size: 20Gi
EOF
    fi

    if [ ! -f "${config_base}/gnocchi/gnocchi-helm-overrides.yaml" ]; then
        cat > "${config_base}/gnocchi/gnocchi-helm-overrides.yaml" <<EOF
---
pod:
  resources:
    enabled: false
conf:
  gnocchi:
    metricd:
      workers: 1
  gnocchi_api_wsgi:
    wsgi:
      processes: 1
      threads: 1
EOF
    fi

    if [ ! -f "${config_base}/heat/heat-helm-overrides.yaml" ]; then
        cat > "${config_base}/heat/heat-helm-overrides.yaml" <<EOF
---
pod:
  resources:
    enabled: false
conf:
  heat:
    DEFAULT:
      num_engine_workers: 1
    heat_api:
      workers: 1
    heat_api_cloudwatch:
      workers: 1
    heat_api_cfn:
      workers: 1
    oslo_messaging_notifications:
      driver: noop
  heat_api_cfn_uwsgi:
    uwsgi:
      processes: 1
      threads: 1
  heat_api_uwsgi:
    uwsgi:
      processes: 1
      threads: 1
EOF
    fi

    if [ ! -f "${config_base}/keystone/keystone-helm-overrides.yaml" ]; then
        cat > "${config_base}/keystone/keystone-helm-overrides.yaml" <<EOF
---
pod:
  resources:
    enabled: false
conf:
  keystone_api_wsgi:
    wsgi:
      processes: 1
      threads: 1
  keystone:
    oslo_messaging_notifications:
      driver: noop
EOF
    fi

    if [ ! -f "${config_base}/neutron/neutron-helm-overrides.yaml" ]; then
        cat > "${config_base}/neutron/neutron-helm-overrides.yaml" <<EOF
---
pod:
  resources:
    enabled: false
conf:
  neutron:
    DEFAULT:
      api_workers: 1
      rpc_workers: 1
      rpc_state_report_workers: 1
    oslo_messaging_notifications:
      driver: noop
EOF
    fi

    if [ ! -f "${config_base}/magnum/magnum-helm-overrides.yaml" ]; then
        cat > "${config_base}/magnum/magnum-helm-overrides.yaml" <<EOF
---
pod:
  resources:
    enabled: false
conf:
  magnum_api_uwsgi:
    uwsgi:
      processes: 1
      threads: 1
EOF
    fi

    if [ ! -f "${config_base}/nova/nova-helm-overrides.yaml" ]; then
        if [ "${HYPERCONVERGED_CINDER_VOLUME:-false}" = "true" ]; then
            cat > "${config_base}/nova/nova-helm-overrides.yaml" <<EOF
---
pod:
  resources:
    enabled: false
conf:
  enable_iscsi: true
  nova:
    DEFAULT:
      osapi_compute_workers: 1
      metadata_workers: 1
    conductor:
      workers: 1
    schedule:
      workers: 1
    oslo_messaging_notifications:
      driver: noop
    libvirt:
      virt_type: qemu
      images_type: qcow2
      images_path: /var/lib/nova/instances
  nova_api_uwsgi:
    uwsgi:
      processes: 1
      threads: 1
  nova_metadata_uwsgi:
    uwsgi:
      processes: 1
      threads: 1
EOF
        else
            cat > "${config_base}/nova/nova-helm-overrides.yaml" <<EOF
---
pod:
  resources:
    enabled: false
conf:
  enable_iscsi: false
  nova:
    DEFAULT:
      osapi_compute_workers: 1
      metadata_workers: 1
    conductor:
      workers: 1
    schedule:
      workers: 1
    oslo_messaging_notifications:
      driver: noop
    libvirt:
      virt_type: qemu
      images_type: qcow2
      images_path: /var/lib/nova/instances
  nova_api_uwsgi:
    uwsgi:
      processes: 1
      threads: 1
  nova_metadata_uwsgi:
    uwsgi:
      processes: 1
      threads: 1
EOF
        fi
    fi

    if [ ! -f "${config_base}/octavia/octavia-helm-overrides.yaml" ]; then
        cat > "${config_base}/octavia/octavia-helm-overrides.yaml" <<EOF
---
pod:
  resources:
    enabled: false
conf:
  octavia:
    DEFAULT:
      debug: true
    oslo_messaging_notifications:
      driver: noop
    controller_worker:
      loadbalancer_topology: SINGLE
      workers: 1
  octavia_api_uwsgi:
    uwsgi:
      processes: 1
      threads: 1
EOF
    fi

    if [ ! -f "${config_base}/placement/placement-helm-overrides.yaml" ]; then
        cat > "${config_base}/placement/placement-helm-overrides.yaml" <<EOF
---
pod:
  resources:
    enabled: false
conf:
  placement:
    oslo_messaging_notifications:
      driver: noop
  placement_api_uwsgi:
    uwsgi:
      processes: 1
      threads: 1
EOF
    fi

    if [ ! -f "${config_base}/masakari/masakari-helm-overrides.yaml" ]; then
        cat > "${config_base}/masakari/masakari-helm-overrides.yaml" <<EOF
---
pod:
  resources:
    enabled: false
conf:
  masakari:
    oslo_messaging_notifications:
      driver: noop
EOF
    fi

    if [ ! -f "${config_base}/manila/manila-helm-overrides.yaml" ]; then
        cat > "${config_base}/manila/manila-helm-overrides.yaml" <<EOF
---
pod:
  resources:
    enabled: false
bootstrap:
  enabled: false
conf:
  manila:
    oslo_messaging_notifications:
      driver: noop
EOF
    fi

    if [ ! -f "${config_base}/cloudkitty/cloudkitty-helm-overrides.yaml" ]; then
        cat > "${config_base}/cloudkitty/cloudkitty-helm-overrides.yaml" <<EOF
---
pod:
  resources:
    enabled: false
conf:
  cloudkitty:
    oslo_messaging_notifications:
      driver: noop
  cloudkitty_api_uwsgi:
    uwsgi:
      processes: 1
      threads: 1
EOF
    fi

    if [ ! -f "${config_base}/freezer/freezer-helm-overrides.yaml" ]; then
        cat > "${config_base}/freezer/freezer-helm-overrides.yaml" <<EOF
---
pod:
  resources:
    enabled: false
conf:
  freezer_api_uwsgi:
    uwsgi:
      processes: 1
  freezer:
    oslo_messaging_notifications:
      driver: noop
EOF
    fi

    if [ ! -f "${config_base}/zaqar/zaqar-helm-overrides.yaml" ]; then
        cat > "${config_base}/zaqar/zaqar-helm-overrides.yaml" <<EOF
---
pod:
  resources:
    enabled: false
conf:
  zaqar_api_uwsgi:
    uwsgi:
      processes: 1
  zaqar:
    oslo_messaging_notifications:
      driver: noop
EOF
    fi
}

function writeEndpointsConfig() {
    # Write endpoints configuration for external access
    # Usage: writeEndpointsConfig <gateway_domain> [config_path]
    local gateway_domain="$1"
    local config_path="${2:-/etc/genestack/helm-configs/global_overrides/endpoints.yaml}"

    if [ ! -f "${config_path}" ]; then
        cat > "${config_path}" <<EOF
_region: &region RegionOne

pod:
  resources:
    enabled: false

endpoints:
  baremetal:
    host_fqdn_override:
      public:
        tls: {}
        host: ironic.${gateway_domain}
    port:
      api:
        public: 443
    scheme:
      public: https
  compute:
    host_fqdn_override:
      public:
        tls: {}
        host: nova.${gateway_domain}
    port:
      api:
        public: 443
    scheme:
      public: https
  compute_metadata:
    host_fqdn_override:
      public:
        tls: {}
        host: metadata.${gateway_domain}
    port:
      metadata:
        public: 443
    scheme:
      public: https
  compute_novnc_proxy:
    host_fqdn_override:
      public:
        tls: {}
        host: novnc.${gateway_domain}
    port:
      novnc_proxy:
        public: 443
    scheme:
      public: https
  cloudformation:
    host_fqdn_override:
      public:
        tls: {}
        host: cloudformation.${gateway_domain}
    port:
      api:
        public: 443
    scheme:
      public: https
  cloudwatch:
    host_fqdn_override:
      public:
        tls: {}
        host: cloudwatch.${gateway_domain}
    port:
      api:
        public: 443
    scheme:
      public: https
  container_infra:
    host_fqdn_override:
      public:
        tls: {}
        host: magnum.${gateway_domain}
    port:
      api:
        public: 443
    scheme:
      public: https
  key_manager:
    host_fqdn_override:
      public:
        tls: {}
        host: barbican.${gateway_domain}
    port:
      api:
        public: 443
    scheme:
      public: https
  dashboard:
    host_fqdn_override:
      public:
        tls: {}
        host: horizon.${gateway_domain}
    port:
      web:
        public: 443
    scheme:
      public: https
  metric:
    host_fqdn_override:
      public:
        tls: {}
        host: gnocchi.${gateway_domain}
    port:
      api:
        public: 443
    scheme:
      public: https
  reservation:
    host_fqdn_override:
      public:
        tls: {}
        host: blazar.${gateway_domain}
    port:
      api:
        public: 443
    scheme:
      public: https
  backup:
    host_fqdn_override:
      public:
        tls: {}
        host: freezer.${gateway_domain}
    port:
      api:
        public: 443
    scheme:
      public: https
  rating:
    host_fqdn_override:
      public:
        tls: {}
        host: cloudkitty.${gateway_domain}
    port:
      api:
        public: 443
    scheme:
      public: https
  instance_ha:
    host_fqdn_override:
      public:
        tls: {}
        host: masakari.${gateway_domain}
    port:
      api:
        public: 443
    scheme:
      public: https
  identity:
    auth:
      admin:
        region_name: *region
      test:
        region_name: *region
      barbican:
        region_name: *region
      blazar:
        region_name: *region
      cinder:
        region_name: *region
      trove:
        region_name: *region
      ceilometer:
        region_name: *region
      cloudkitty:
        region_name: *region
      glance:
        region_name: *region
      gnocchi:
        region_name: *region
      heat:
        region_name: *region
      heat_trustee:
        region_name: *region
      heat_stack_user:
        region_name: *region
      ironic:
        region_name: *region
      magnum:
        region_name: *region
      masakari:
        region_name: *region
      manila:
        region_name: *region
      neutron:
        region_name: *region
      nova:
        region_name: *region
      placement:
        region_name: *region
      octavia:
        region_name: *region
      freezer:
        region_name: *region
      zaqar:
        region_name: *region
    host_fqdn_override:
      public:
        tls: {}
        host: keystone.${gateway_domain}
    port:
      api:
        public: 443
        admin: 80
    scheme:
      public: https
  ingress:
    port:
      ingress:
        public: 443
  image:
    host_fqdn_override:
      public:
        tls: {}
        host: glance.${gateway_domain}
    port:
      api:
        public: 443
    scheme:
      public: https
  load_balancer:
    host_fqdn_override:
      public:
        tls: {}
        host: octavia.${gateway_domain}
    port:
      api:
        public: 443
    scheme:
      public: https
  network:
    host_fqdn_override:
      public:
        tls: {}
        host: neutron.${gateway_domain}
    port:
      api:
        public: 443
    scheme:
      public: https
  orchestration:
    host_fqdn_override:
      public:
        tls: {}
        host: heat.${gateway_domain}
    port:
      api:
        public: 443
    scheme:
      public: https
  placement:
    host_fqdn_override:
      public:
        tls: {}
        host: placement.${gateway_domain}
    port:
      api:
        public: 443
    scheme:
      public: https
  share:
    host_fqdn_override:
      public:
        tls: {}
        host: manila.${gateway_domain}
    port:
      api:
        public: 443
    scheme:
      public: https
  sharev2:
    host_fqdn_override:
      public:
        tls: {}
        host: manila.${gateway_domain}
    port:
      api:
        public: 443
    scheme:
      public: https
  volume:
    host_fqdn_override:
      public:
        tls: {}
        host: cinder.${gateway_domain}
    port:
      api:
        public: 443
    scheme:
      public: https
  volumev2:
    host_fqdn_override:
      public:
        tls: {}
        host: cinder.${gateway_domain}
    port:
      api:
        public: 443
    scheme:
      public: https
  volumev3:
    host_fqdn_override:
      public:
        tls: {}
        host: cinder.${gateway_domain}
    port:
      api:
        public: 443
    scheme:
      public: https
  database:
    host_fqdn_override:
      public:
        tls: {}
        host: trove.${gateway_domain}
    port:
      api:
        public: 443
    scheme:
      public: https
  messaging:
    host_fqdn_override:
      public:
        tls: {}
        host: zaqar.${gateway_domain}
    port:
      api:
        public: 443
    scheme:
      public: https
EOF
    fi
}

function createPostSetupResources() {
    # Create post-setup OpenStack resources (flavor, flat network, subnet)
    # Usage: createPostSetupResources <lab_name_prefix>
    local lab_prefix="$1"

    if openstack --version; then
        echo "OpenStack CLI found"
    else
        echo "Sourcing OpenStack RC file..."
        source /opt/genestack/scripts/genestack.rc
    fi

    echo "Running Generic Genestack post setup..."

    if [ ! -f ~/.config/openstack ]; then
        sudo mkdir -p ~/.config/openstack
        sudo cp /root/.config/openstack/clouds.yaml ~/.config/openstack
        sudo chown $(id -u):$(id -g) ~/.config
    fi

    # Create test flavor
    if ! openstack --os-cloud default flavor show ${lab_prefix}-test 2>/dev/null; then
        openstack --os-cloud default flavor create ${lab_prefix}-test \
            --public \
            --ram 2048 \
            --disk 10 \
            --vcpus 2
    fi

    # Create flat provider network
    if ! openstack --os-cloud default network show flat 2>/dev/null; then
        openstack --os-cloud default network create \
            --share \
            --availability-zone-hint az1 \
            --external \
            --provider-network-type flat \
            --provider-physical-network physnet1 \
            flat
    fi

    # Create flat subnet
    if ! openstack --os-cloud default subnet show flat_subnet 2>/dev/null; then
        openstack --os-cloud default subnet create \
            --subnet-range 192.168.102.0/24 \
            --gateway 192.168.102.1 \
            --dns-nameserver 1.1.1.1 \
            --allocation-pool start=192.168.102.100,end=192.168.102.109 \
            --dhcp \
            --network flat \
            flat_subnet
    fi
}

function installK9s() {
    # Install k9s locally
    echo "Installing k9s..."
    if [ ! -e "/usr/bin/k9s" ]; then
        sudo wget -q https://github.com/derailed/k9s/releases/latest/download/k9s_linux_amd64.deb -O /tmp/k9s_linux_amd64.deb
        sudo apt install -y /tmp/k9s_linux_amd64.deb
        sudo rm /tmp/k9s_linux_amd64.deb
    fi

    if [ ! -d ~/.kube ]; then
        mkdir ~/.kube
        sudo cp -i /etc/kubernetes/admin.conf ~/.kube/config 2>/dev/null || true
        sudo chown $(id -u):$(id -g) ~/.kube/config 2>/dev/null || true
    fi
}

function runGenestackSetup() {
    # Run Genestack infrastructure and OpenStack setup locally
    # Usage: runGenestackSetup <gateway_domain> <acme_email>

    local gateway_domain="$1"
    local acme_email="$2"

    echo "Installing OpenStack Infrastructure"
    sudo LONGHORN_STORAGE_REPLICAS=1 \
         GATEWAY_DOMAIN="${gateway_domain}" \
         ACME_EMAIL="${acme_email}" \
         HYPERCONVERGED=true \
         /opt/genestack/bin/setup-infrastructure.sh

    echo "Installing OpenStack"
    sudo /opt/genestack/bin/setup-openstack.sh
    sudo /opt/genestack/bin/setup-openstack-rc.sh
}

#############################################################################
# Remote Configuration Functions (for SSH-based setup on jump hosts)
#############################################################################

function configureGenestackRemote() {
    # Configure Genestack on a remote jump host via SSH
    # Usage: configureGenestackRemote <ssh_user> <jump_host_ip> <metal_lb_ip> <gateway_domain>
    #
    # This function SSHes to the jump host and writes all the service helm overrides
    # and endpoints configuration. It's used by both Kubespray and Talos scripts.

    local ssh_user="$1"
    local jump_host="$2"
    local metal_lb_ip="$3"
    local gateway_domain="$4"
    local os_config="$(cat ${SCRIPT_DIR}/../../openstack-components.yaml)"

    echo "Configuring Genestack service overrides on jump host..."

    {
        declare -f writeMetalLBConfig
        declare -f writeServiceHelmOverrides
        declare -f writeEndpointsConfig
        declare -f writeOpenstackComponentsConfig
        declare -f ensureYq
        declare -f installYq

        cat <<EOF
export HYPERCONVERGED_CINDER_VOLUME=$HYPERCONVERGED_CINDER_VOLUME
export INCLUDE_LIST=("${INCLUDE_LIST[@]}")
export EXCLUDE_LIST=("${EXCLUDE_LIST[@]}")
set -e
ensureYq
writeMetalLBConfig '${metal_lb_ip}' '/etc/genestack/manifests/metallb/metallb-openstack-service-lb.yml'
writeServiceHelmOverrides '/etc/genestack/helm-configs'
writeEndpointsConfig '${gateway_domain}' '/etc/genestack/helm-configs/global_overrides/endpoints.yaml'
writeOpenstackComponentsConfig '/etc/genestack/openstack-components.yaml' "${os_config}"
echo 'Genestack service configuration complete'
EOF
    } | ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t "${ssh_user}@${jump_host}" bash
}

function runGenestackSetupRemote() {
    # Run Genestack infrastructure and OpenStack setup on a remote jump host
    # Usage: runGenestackSetupRemote <ssh_user> <jump_host_ip> <gateway_domain> <acme_email>

    local ssh_user="$1"
    local jump_host="$2"
    local gateway_domain="$3"
    local acme_email="$4"

    echo "Installing OpenStack Infrastructure on jump host..."

    {
        declare -f runGenestackSetup
        declare -f ensureYq
        declare -f installYq

        cat <<EOF
set -e
ensureYq
runGenestackSetup "${gateway_domain}" "${acme_email}"
EOF
    } | ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t ${ssh_user}@${jump_host} bash
}

function waitForOpenStackAPIsReady() {
    # Wait for Nova and Neutron APIs to be ready
    # Usage: waitForOpenStackAPIsReady [timeout_seconds]
    #
    # This function waits for the Nova and Neutron API services to become
    # available and responsive before proceeding with post-setup tasks.

    local timeout="${1:-300}"
    local interval=10
    local elapsed=0

    echo "Waiting for OpenStack APIs to be ready (timeout: ${timeout}s)..."

    if openstack --version; then
        echo "OpenStack CLI found"
    else
        echo "Sourcing OpenStack RC file..."
        source /opt/genestack/scripts/genestack.rc
    fi

    echo "Running Generic Genestack post setup..."

    if [ ! -f ~/.config/openstack ]; then
        sudo mkdir -p ~/.config/openstack
        sudo cp /root/.config/openstack/clouds.yaml ~/.config/openstack
        sudo chown $(id -u):$(id -g) ~/.config
    fi

    # Wait for Keystone (authentication) to be ready first
    echo "  Checking Keystone authentication..."
    while [[ $elapsed -lt $timeout ]]; do
        if openstack --os-cloud default token issue >/dev/null 2>&1; then
            echo "  Keystone is ready"
            break
        fi
        echo "  Keystone not ready yet, waiting ${interval}s... (${elapsed}s/${timeout}s)"
        sleep $interval
        ((elapsed+=interval))
    done

    if [[ $elapsed -ge $timeout ]]; then
        echo "ERROR: Timeout waiting for Keystone API"
        return 1
    fi

    # Wait for Nova API to be ready
    echo "  Checking Nova API..."
    elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        if openstack --os-cloud default compute service list >/dev/null 2>&1; then
            # Verify at least one compute service is up
            local nova_up=$(openstack --os-cloud default compute service list -f value -c State 2>/dev/null | grep -c "up" || echo "0")
            if [[ $nova_up -gt 0 ]]; then
                echo "  Nova API is ready (${nova_up} service(s) up)"
                break
            fi
        fi
        echo "  Nova API not ready yet, waiting ${interval}s... (${elapsed}s/${timeout}s)"
        sleep $interval
        ((elapsed+=interval))
    done

    if [[ $elapsed -ge $timeout ]]; then
        echo "ERROR: Timeout waiting for Nova API"
        return 1
    fi

    # Wait for Neutron API to be ready
    echo "  Checking Neutron API..."
    elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        if openstack --os-cloud default network agent list >/dev/null 2>&1; then
            # Verify at least one network agent is alive
            local neutron_alive=$(openstack --os-cloud default network agent list -f value -c Alive 2>/dev/null | grep -ci "true" || echo "0")
            if [[ $neutron_alive -gt 0 ]]; then
                echo "  Neutron API is ready (${neutron_alive} agent(s) alive)"
                break
            fi
        fi
        echo "  Neutron API not ready yet, waiting ${interval}s... (${elapsed}s/${timeout}s)"
        sleep $interval
        ((elapsed+=interval))
    done

    if [[ $elapsed -ge $timeout ]]; then
        echo "ERROR: Timeout waiting for Neutron API"
        return 1
    fi

    echo "OpenStack APIs are ready"
    return 0
}

function waitForOpenStackAPIsReadyRemote() {
    # Wait for Nova and Neutron APIs on a remote jump host
    # Usage: waitForOpenStackAPIsReadyRemote <ssh_user> <jump_host_ip> [timeout_seconds]

    local ssh_user="$1"
    local jump_host="$2"
    local timeout="${3:-300}"

    echo "Waiting for OpenStack APIs on jump host..."

    {
        declare -f waitForOpenStackAPIsReady

        cat <<EOF
set -e
waitForOpenStackAPIsReady "${timeout}"
EOF
    } | ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t ${ssh_user}@${jump_host} bash
}

function createPostSetupResourcesRemote() {
    # Run post-setup configuration on a remote jump host
    # Usage: createPostSetupResourcesRemote <ssh_user> <jump_host_ip> <lab_name_prefix>

    local ssh_user="$1"
    local jump_host="$2"
    local lab_prefix="$3"

    echo "Running post-setup configuration on jump host..."

    {
        declare -f createPostSetupResources
        declare -f ensureYq
        declare -f installYq

        cat <<EOF
set -e
ensureYq
createPostSetupResources "${lab_prefix}"
EOF

    } | ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t ${ssh_user}@${jump_host} bash
}

function installK9sRemote() {
    # Install k9s on a remote jump host
    # Usage: installK9sRemote <ssh_user> <jump_host_ip>

    local ssh_user="$1"
    local jump_host="$2"

    echo "Installing k9s on jump host..."

    {
        declare -f installK9s

        cat <<EOF
set -e
installK9s
EOF
    } | ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t ${ssh_user}@${jump_host} bash
}

function cloneGenestackOnJumpHost() {
    # Clone the Genestack repository on the jump host
    # Usage: cloneGenestackOnJumpHost
    ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t ${SSH_USERNAME}@${JUMP_HOST_VIP} <<EOC
    set -e
    if [ ! -d "/opt/genestack" ]; then
        sudo git clone --recurse-submodules -j4 https://github.com/rackerlabs/genestack /opt/genestack
    fi
    echo "Updating Genestack repository on jump host and initializing submodules..."
    sudo git config --global --add safe.directory /opt/genestack
    pushd /opt/genestack
        sudo git submodule update --init --recursive
    popd
EOC
}

function cinderVolumeSetup() {
    local net_name="${LAB_NAME_PREFIX}-net"

    # capture IPs (not VIP) for each server
    IP_0=$(openstack server show ${LAB_NAME_PREFIX}-0 -f json | jq -r '.addresses' | jq --arg net_name "${net_name}" -r '.[$net_name][0]')
    IP_1=$(openstack server show ${LAB_NAME_PREFIX}-1 -f json | jq -r '.addresses' | jq --arg net_name "${net_name}" -r '.[$net_name][0]')
    IP_2=$(openstack server show ${LAB_NAME_PREFIX}-2 -f json | jq -r '.addresses' | jq --arg net_name "${net_name}" -r '.[$net_name][0]')
    JUMP_HOST_IP=$(openstack server show ${LAB_NAME_PREFIX}-0 -f json | jq -r '.addresses' | jq --arg net_name "${net_name}" -r '.[$net_name][1]')

    # VM specific setup
    echo "[VM] Updating ~/.ssh/config"
    cat >> ~/.ssh/config << SSH_CONFIG_EOF
Host *
    User ubuntu
    ForwardAgent yes
    ForwardX11Trusted yes
    AddKeysToAgent yes
    IdentityFile /home/ubuntu/.ssh/${LAB_NAME_PREFIX}-key.pem
    ProxyCommand none
    TCPKeepAlive yes
    ServerAliveInterval 300
    Ciphers aes128-ctr,aes192-ctr,aes256-ctr,aes128-cbc,3des-cbc
    MACs hmac-sha2-512,hmac-sha2-256,hmac-md5,hmac-sha1,umac-64@openssh.com
    KexAlgorithms +diffie-hellman-group1-sha1
SSH_CONFIG_EOF

    echo "[VM] Removing ~/.ssh/known_hosts"
    rm -f ~/.ssh/known_hosts

    # Jump Host setup
    PEM_CONTENT=$(cat ~/.ssh/${LAB_NAME_PREFIX}-key.pem)
    PUB_CONTENT=$(cat ~/.ssh/${LAB_NAME_PREFIX}-key.pub)

    {
        cat << JUMP_HOST_EOF
source /opt/genestack/scripts/genestack.rc

echo "[JUMP_HOST] Setup for admin operations"
sudo mkdir -p ~/.config/openstack
sudo cp /root/.config/openstack/clouds.yaml ~/.config/openstack/
sudo chown -R $(id -u):$(id -g) ~/.config

echo "[JUMP_HOST] Updating ~/.ssh/config"
cat >> ~/.ssh/config << SSH_CONFIG_EOF
Host *
    User ubuntu
    ForwardAgent yes
    ForwardX11Trusted yes
    AddKeysToAgent yes
    IdentityFile /home/ubuntu/.ssh/${LAB_NAME_PREFIX}-key.pem
    ProxyCommand none
    TCPKeepAlive yes
    ServerAliveInterval 300
    Ciphers aes128-ctr,aes192-ctr,aes256-ctr,aes128-cbc,3des-cbc
    MACs hmac-sha2-512,hmac-sha2-256,hmac-md5,hmac-sha1,umac-64@openssh.com
    KexAlgorithms +diffie-hellman-group1-sha1
SSH_CONFIG_EOF

echo "[JUMP_HOST] Creating ssh key"
echo "${PEM_CONTENT}" >> ~/.ssh/${LAB_NAME_PREFIX}-key.pem
echo "${PUB_CONTENT}" >> ~/.ssh/${LAB_NAME_PREFIX}-key.pub
chmod 600 ~/.ssh/${LAB_NAME_PREFIX}-key.pem
chmod 644 ~/.ssh/${LAB_NAME_PREFIX}-key.pub

echo "[JUMP_HOST] Updating /etc/hosts"
sudo sh -c 'cat >> /etc/hosts' << ETC_HOSTS_EOF
${IP_0} ${LAB_NAME_PREFIX}-0.cluster.local ${LAB_NAME_PREFIX}-0
${IP_1} ${LAB_NAME_PREFIX}-1.cluster.local ${LAB_NAME_PREFIX}-1
${IP_2} ${LAB_NAME_PREFIX}-2.cluster.local ${LAB_NAME_PREFIX}-2
ETC_HOSTS_EOF

echo "[JUMP_HOST] Creating PV/VG"
sudo pvcreate /dev/vdd
sudo vgcreate cinder-volumes-1 /dev/vdd
JUMP_HOST_EOF
    } | ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t "ubuntu@${JUMP_HOST_IP}" bash

    # Secondary Kube node setup
    {
        cat << NODE_1_EOF
echo "[Node 1] Creating PV/VG"
ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t ubuntu@${LAB_NAME_PREFIX}-1 "sudo pvcreate /dev/vdd && sudo vgcreate cinder-volumes-1 /dev/vdd"
NODE_1_EOF
    } | ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t "ubuntu@${JUMP_HOST_IP}" bash
    {
        cat << NODE_2_EOF
echo "[Node 2] Creating PV/VG"
ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t ubuntu@${LAB_NAME_PREFIX}-2 "sudo pvcreate /dev/vdd && sudo vgcreate cinder-volumes-1 /dev/vdd"
NODE_2_EOF
    } | ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t "ubuntu@${JUMP_HOST_IP}" bash

    # Ansible playbook time
    {
        cat << ANSIBLE_EOF
source /opt/genestack/scripts/genestack.rc

echo "[JUMP_HOST] Running cinder install script"
sudo /opt/genestack/bin/install-cinder.sh

echo "[JUMP_HOST] Running cinder volumes playbook (2 times in case of failed steps in first run)"
ansible-playbook -i /etc/genestack/inventory/inventory.yaml \
    -e "cinder_storage_network_interface=ansible_enp3s0 cinder_storage_network_interface_secondary=ansible_enp3s0" \
    /opt/genestack/ansible/playbooks/deploy-cinder-volumes-reference.yaml -f15
ansible-playbook -i /etc/genestack/inventory/inventory.yaml \
    -e "cinder_storage_network_interface=ansible_enp3s0 cinder_storage_network_interface_secondary=ansible_enp3s0" \
    /opt/genestack/ansible/playbooks/deploy-cinder-volumes-reference.yaml -f15

echo "[JUMP_HOST] Creating volume type and qos"
openstack volume type create \
    --description 'Standard with LUKS encryption' \
    --encryption-provider luks \
    --encryption-cipher aes-xts-plain64 \
    --encryption-key-size 256 \
    --encryption-control-location front-end \
    --property volume_backend_name=LVM_iSCSI \
    --property provisioning:max_vol_size='199' \
    --property provisioning:min_vol_size='1' \
    Standard
openstack volume qos create \
    --property read_iops_sec_per_gb='20' \
    --property write_iops_sec_per_gb='20' \
    Standard-Block
openstack volume qos associate Standard-Block Standard
openstack volume type set --private __DEFAULT__
ANSIBLE_EOF
    } | ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t "ubuntu@${JUMP_HOST_IP}" bash
}
