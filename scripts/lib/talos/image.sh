#!/usr/bin/env bash
# Talos image download and upload functions

# Each lib module resolves its own location to find helpers.sh
_SCRIPT_LOCAL="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "${_SCRIPT_LOCAL}/../helpers.sh"

function downloadTalosImage() {
    # Download a Talos OS image (pre-baked with the configured schematic)
    local image_url="https://factory.talos.dev/image/${TALOS_SCHEMATIC_ID}/${TALOS_VERSION}/openstack-${TALOS_ARCH}.raw.xz"
    local image_file="/tmp/talos-${TALOS_VERSION}-openstack-${TALOS_ARCH}.raw.xz"
    local raw_file="/tmp/talos-${TALOS_VERSION}-openstack-${TALOS_ARCH}.raw"

    echo "Downloading Talos image from factory..."
    curl -L -o "${image_file}" "${image_url}"

    echo "Decompressing Talos image..."
    xz -d "${image_file}"
}

function uploadTalosImage() {
    # Uploads the raw Talos disk image to OpenStack Glance
    local raw_file="${1:-/tmp/talos-${TALOS_VERSION}-openstack-${TALOS_ARCH}.raw}"
    echo "Uploading Talos image to Glance as '${TALOS_IMAGE_NAME}'..."
    openstack image create "${TALOS_IMAGE_NAME}" \
        --public \
        --disk-format raw \
        --container-format bare \
        --file "${raw_file}" \
        --property hardware_disk_bus=usb \
        --property hardware_rng_model=virtio \
        --property os_type=linux \
        --property os_distro=talos \
        --property hw_vif_multiqueue_enabled=true \
        --property hw_qemu_guest_agent=yes \
        --property hypervisor_type=kvm \
        --property hw_machine_type=q35 \
        --property hw_firmware_type=uefi \
        --property os_require_quiesce=yes \
        --property os_admin_user=talos \
        --property os_version=18.2 \
        --tags siderolabs/iscsi-tools siderolabs/util-linux-tools siderolabs/qemu-guest-agent \
        --progress
}
