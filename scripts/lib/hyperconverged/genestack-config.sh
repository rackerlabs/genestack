#!/usr/bin/env bash
# Genestack configuration write functions
# Sourced from helpers.sh or orchestrator scripts

# Each lib module resolves its own location to find helpers.sh
_SCRIPT_LOCAL="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "${_SCRIPT_LOCAL}/../helpers.sh"
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
    # Ensure per-service override directories exist before writing files.
    mkdir -p \
      "${config_base}/envoyproxy-gateway" \
      "${config_base}/barbican" \
      "${config_base}/blazar" \
      "${config_base}/cinder" \
      "${config_base}/cloudkitty" \
      "${config_base}/freezer" \
      "${config_base}/glance" \
      "${config_base}/gnocchi" \
      "${config_base}/heat" \
      "${config_base}/keystone" \
      "${config_base}/magnum" \
      "${config_base}/manila" \
      "${config_base}/masakari" \
      "${config_base}/neutron" \
      "${config_base}/nova" \
      "${config_base}/octavia" \
      "${config_base}/placement" \
      "${config_base}/trove" \
      "${config_base}/zaqar"

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
    mkdir -p "$(dirname "${config_path}")"

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
