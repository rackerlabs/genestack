#!/usr/bin/env bash
set -e

export GENESTACK_INSTALL_TELEMETRY=${GENESTACK_INSTALL_TELEMETRY:-false}

# Track the PIDs of the services deploying in parallel
pids=()

function runTrackErator() {
    exec "${1}" &
    pids+=($!)
}

function waitErator () {
    for pid in ${pids[*]}; do
        wait "${pid}"
    done
}

# Block on Keystone
/opt/genestack/bin/install-keystone.sh

# Run the rest of the services in parallel
runTrackErator /opt/genestack/bin/install-glance.sh
runTrackErator /opt/genestack/bin/install-heat.sh
runTrackErator /opt/genestack/bin/install-barbican.sh
runTrackErator /opt/genestack/bin/install-cinder.sh
runTrackErator /opt/genestack/bin/install-placement.sh
runTrackErator /opt/genestack/bin/install-nova.sh
runTrackErator /opt/genestack/bin/install-neutron.sh
runTrackErator /opt/genestack/bin/install-magnum.sh
runTrackErator /opt/genestack/bin/install-octavia.sh

# Install telemetry services
if [ "${GENESTACK_INSTALL_TELEMETRY}" = true ]; then
    runTrackErator /opt/genestack/bin/install-ceilometer.sh
    runTrackErator /opt/genestack/bin/install-gnocchi.sh
fi

waitErator

# Install skyline after all services are up
/opt/genestack/bin/install-skyline.sh
