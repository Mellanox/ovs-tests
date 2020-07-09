#!/bin/bash
#
# Test ovs with vxlan rules and dump flows with dpctl
#
# Bug SW #1465595: ovs-dpctl dump-flows command failed when using non default vxlan port

my_dir="$(dirname "$0")"

function ovs_dpctl_dump_flows() {
    local args=$@
    ovs-dpctl dump-flows $args type=tc 2>/dev/null
    [[ $? -ne 0 ]] && ovs-dpctl dump-flows $args type=offloaded
}

ovs_dpctl_dump_flows 2>&1 | grep -q "Invalid argument 'type'"
if [ $? -eq 0 ]; then
    echo "ERROR: Test not relevant for this version of ovs"
    exit 1
fi

USE_DPCTL=1
. $my_dir/test-ovs-vxlan-in-ns.sh
