#!/usr/bin/env bash
# shellcheck disable=SC2124,SC2145,SC2294,SC2086,SC2087,SC2155

set -o pipefail
set -e
SECONDS=0

if [ -z "${OS_CLOUD}" ]; then
  read -rp "Enter name of the cloud configuration used for this build [default]: " OS_CLOUD
  export OS_CLOUD="${OS_CLOUD:-default}"
fi

function serverDelete() {
  if ! openstack server delete "${1}" 2> /dev/null; then
    echo "Failed to delete server ${1}"
  fi
}

function portDelete() {
  if ! openstack port delete "${1}" 2> /dev/null; then
    echo "Failed to delete port ${1}"
  fi
}

function securityGroupDelete() {
  if ! openstack security group delete "${1}" 2> /dev/null; then
    echo "Failed to delete security group ${1}"
  fi
}

function networkDelete() {
  if ! openstack network delete "${1}" 2> /dev/null; then
    echo "Failed to delete network ${1}"
  fi
}

function subnetDelete() {
  if ! openstack subnet delete "${1}" 2> /dev/null; then
    echo "Failed to delete subnet ${1}"
  fi
}

for i in $(openstack floating ip list --router hyperconverged-router -f value -c "Floating IP Address"); do
  if ! openstack floating ip unset "${i}" 2> /dev/null; then
    echo "Failed to unset floating ip ${i}"
  fi
  if ! openstack floating ip delete "${i}" 2> /dev/null; then
    echo "Failed to delete floating ip ${i}"
  fi
done

serverDelete hyperconverged-2
serverDelete hyperconverged-1
serverDelete hyperconverged-0

if ! openstack keypair delete hyperconverged-key 2> /dev/null; then
  echo "Failed to delete keypair hyperconverged-key"
fi

portDelete hyperconverged-2-compute-port
portDelete hyperconverged-1-compute-port
portDelete hyperconverged-0-compute-port
for i in {100..109}; do
  portDelete "hyperconverged-0-compute-float-${i}-port"
done
portDelete hyperconverged-2-mgmt-port
portDelete hyperconverged-1-mgmt-port
portDelete hyperconverged-0-mgmt-port
portDelete metallb-vip-0-port

securityGroupDelete hyperconverged-jump-secgroup
securityGroupDelete hyperconverged-http-secgroup
securityGroupDelete hyperconverged-secgroup

if ! openstack router remove subnet hyperconverged-router hyperconverged-subnet 2> /dev/null; then
  echo "Failed to remove hyperconverged-subnet from router hyperconverged-router"
fi
if ! openstack router remove subnet hyperconverged-router hyperconverged-compute-subnet 2> /dev/null; then
  echo "Failed to remove hyperconverged-compute-subnet from router hyperconverged-router"
fi
if ! openstack router remove gateway hyperconverged-router PUBLICNET 2> /dev/null; then
  echo "Failed to remove gateway from router hyperconverged-router"
fi
if ! openstack router delete hyperconverged-router 2> /dev/null; then
  echo "Failed to delete router hyperconverged-router"
fi

subnetDelete hyperconverged-compute-subnet
subnetDelete hyperconverged-subnet

networkDelete hyperconverged-compute-net
networkDelete hyperconverged-net

echo "Cleanup complete"
echo "The lab uninstall took ${SECONDS} seconds to complete."
