#!/usr/bin/env bash
# SSH keypair management for hyperconverged lab

# Each lib module resolves its own location to find helpers.sh
_SCRIPT_LOCAL="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "${_SCRIPT_LOCAL}/../helpers.sh"

function createOrUpdateKeypair() {
    local prefix="${LAB_NAME_PREFIX:-genestack}"

    if [ ! -d ~/.ssh ]; then
        _log INFO "Creating SSH directory"
        mkdir -p ~/.ssh
        chmod 700 ~/.ssh
    fi

    if ! openstack keypair show ${prefix}-key -f value -c name >/dev/null 2>&1; then
        if [ ! -f ~/.ssh/${prefix}-key.pem ]; then
            _log INFO "Generating new SSH keypair"
            openstack keypair create ${prefix}-key > ~/.ssh/${prefix}-key.pem 2>/dev/null
            chmod 600 ~/.ssh/${prefix}-key.pem
            openstack keypair show ${prefix}-key --public-key > ~/.ssh/${prefix}-key.pub 2>/dev/null
        else
            if [ -f ~/.ssh/${prefix}-key.pub ]; then
                _log INFO "Re-using existing local key"
                openstack keypair create ${prefix}-key --public-key ~/.ssh/${prefix}-key.pub 2>/dev/null
            fi
        fi
    else
        _log INFO "Keypair ${prefix}-key already exists"
    fi

    ssh-add ~/.ssh/${prefix}-key.pem 2>/dev/null || true
}
