#!/usr/bin/env bash

set -eu

KERN_TAINT=$(cat /proc/sys/kernel/tainted)

mkdir -p /opt/node_exporter/textfile_collector
rm -f /opt/node_exporter/textfile_collector/kernel_tainted.prom

{
echo "# HELP kernel_tainted usage: gathers kernel taint status."
echo "# TYPE kernel_tainted gauge"

echo "kernel_tainted{host=\"$(hostname)\"} $KERN_TAINT"

} >> /opt/node_exporter/textfile_collector/kernel_tainted.prom 2>&1
