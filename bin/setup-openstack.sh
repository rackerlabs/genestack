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
        if ! timeout --preserve-status --verbose 30m tail --pid=${pid} -f /dev/null; then
            echo "==== PROCESS TIMEOUT ====================================="
            cat /proc/${pid}/cmdline | xargs -0 echo
            echo "==== PROCESS TIMEOUT ====================================="
            echo "Timeout after 30 minutes waiting for process ${pid} to finish. Exiting."
            exit 1
        fi
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
runTrackErator /opt/genestack/bin/install-masakari.sh

# Install telemetry services
if [ "${GENESTACK_INSTALL_TELEMETRY}" = true ]; then
    runTrackErator /opt/genestack/bin/install-ceilometer.sh
    runTrackErator /opt/genestack/bin/install-gnocchi.sh
fi

waitErator

# Install skyline after all services are up
/opt/genestack/bin/install-skyline.sh
