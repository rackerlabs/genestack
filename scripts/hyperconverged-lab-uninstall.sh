#!/usr/bin/env bash
# shellcheck disable=SC2124,SC2145,SC2294,SC2086,SC2087,SC2155

set -o pipefail
set -e
SECONDS=0

if [ -z "${OS_CLOUD}" ]; then
  read -rp "Enter name of the cloud configuration used for this build [default]: " OS_CLOUD
  export OS_CLOUD="${OS_CLOUD:-default}"
fi

export LAB_NAME_PREFIX="${LAB_NAME_PREFIX:-hyperconverged}"

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

for i in $(openstack floating ip list --router ${LAB_NAME_PREFIX}-router -f value -c "Floating IP Address"); do
  if ! openstack floating ip unset "${i}" 2> /dev/null; then
    echo "Failed to unset floating ip ${i}"
  fi
  if ! openstack floating ip delete "${i}" 2> /dev/null; then
    echo "Failed to delete floating ip ${i}"
  fi
done

serverDelete ${LAB_NAME_PREFIX}-2
serverDelete ${LAB_NAME_PREFIX}-1
serverDelete ${LAB_NAME_PREFIX}-0

if ! openstack keypair delete ${LAB_NAME_PREFIX}-key 2> /dev/null; then
  echo "Failed to delete keypair ${LAB_NAME_PREFIX}-key"
fi

portDelete ${LAB_NAME_PREFIX}-2-compute-port
portDelete ${LAB_NAME_PREFIX}-1-compute-port
portDelete ${LAB_NAME_PREFIX}-0-compute-port
for i in {100..109}; do
  portDelete "${LAB_NAME_PREFIX}-0-compute-float-${i}-port"
done
portDelete ${LAB_NAME_PREFIX}-2-mgmt-port
portDelete ${LAB_NAME_PREFIX}-1-mgmt-port
portDelete ${LAB_NAME_PREFIX}-0-mgmt-port
portDelete metallb-vip-0-port

securityGroupDelete ${LAB_NAME_PREFIX}-jump-secgroup
securityGroupDelete ${LAB_NAME_PREFIX}-http-secgroup
securityGroupDelete ${LAB_NAME_PREFIX}-secgroup

if ! openstack router remove subnet ${LAB_NAME_PREFIX}-router ${LAB_NAME_PREFIX}-subnet 2> /dev/null; then
  echo "Failed to remove ${LAB_NAME_PREFIX}-subnet from router ${LAB_NAME_PREFIX}-router"
fi
if ! openstack router remove subnet ${LAB_NAME_PREFIX}-router ${LAB_NAME_PREFIX}-compute-subnet 2> /dev/null; then
  echo "Failed to remove ${LAB_NAME_PREFIX}-compute-subnet from router ${LAB_NAME_PREFIX}-router"
fi
if ! openstack router remove gateway ${LAB_NAME_PREFIX}-router PUBLICNET 2> /dev/null; then
  echo "Failed to remove gateway from router ${LAB_NAME_PREFIX}-router"
fi
if ! openstack router delete ${LAB_NAME_PREFIX}-router 2> /dev/null; then
  echo "Failed to delete router ${LAB_NAME_PREFIX}-router"
fi

subnetDelete ${LAB_NAME_PREFIX}-compute-subnet
subnetDelete ${LAB_NAME_PREFIX}-subnet

networkDelete ${LAB_NAME_PREFIX}-compute-net
networkDelete ${LAB_NAME_PREFIX}-net

echo "Cleanup complete"
echo "The lab uninstall took ${SECONDS} seconds to complete."
