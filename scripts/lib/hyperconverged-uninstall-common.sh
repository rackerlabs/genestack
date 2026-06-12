#!/usr/bin/env bash
# shellcheck disable=SC2124,SC2145,SC2294,SC2086,SC2087,SC2155
#
# Hyperconverged Lab Uninstall Common Library
#

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

function _delete_all_ports() {
    local lab_prefix="$1"
    local port_ids
    port_ids=$(openstack port list -f json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for p in data:
    name = p.get('Name') or p.get('name') or ''
    port_id = p.get('ID') or p.get('id') or ''
    if name and '${lab_prefix}' in name and port_id:
        print(port_id)
" 2>/dev/null)
    for port_id in ${port_ids}; do
        if [ -n "${port_id}" ]; then
            openstack port delete ${port_id} >/dev/null 2>&1 || true
        fi
    done
    _log INFO "Ports deleted"
}

function _delete_security_groups() {
    local lab_prefix="$1"
    for sg in $(openstack security group list -f value -c Name 2>/dev/null | grep "${lab_prefix}"); do
        openstack security group rule list ${sg} -f value -c ID 2>/dev/null | while read rid; do
            openstack security group rule delete ${rid} >/dev/null 2>&1 || true
        done
        openstack security group delete ${sg} >/dev/null 2>&1 || true
    done
    _log INFO "Security groups deleted"
}

function _wait_for_servers_term() {
    local max_wait="${1:-180}"
    local elapsed=0
    _log INFO "  Waiting for servers to terminate (max ${max_wait}s)"
    while [ ${elapsed} -lt ${max_wait} ]; do
        all_deleted=true
        for i in 0 1 2; do
            s=$(openstack server show ${LAB_NAME_PREFIX:-hyperconverged}-${i} -f value -c status 2>/dev/null || echo "DELETED")
            if [ "${s}" != "DELETED" ] && [ "${s}" != "ERROR" ]; then
                all_deleted=false
            fi
        done
        if ${all_deleted}; then
            _log INFO "  All servers terminated"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    _log WARN "  Servers may still be deleting"
    return 1
}

function _wait_volumes_term() {
    local max_wait="${1:-120}"
    local elapsed=0
    while [ ${elapsed} -lt ${max_wait} ]; do
        all_gone=true
        for i in 0 1 2; do
            vol_status=$(openstack volume show ${LAB_NAME_PREFIX:-hyperconverged}-${i}-cv1 -f value -c status 2>/dev/null || echo "ERROR")
            if [ "${vol_status}" != "ERROR" ]; then
                all_gone=false
            fi
        done
        if ${all_gone}; then
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    return 1
}
