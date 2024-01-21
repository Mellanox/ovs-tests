#!/bin/bash
#
# Test some ovs function not used by default for coverage.
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

restart_openvswitch

function misc_functions() {
    local cmd
    # short commands
    for cmd in \
        "ovs-vswitchd -h" \
        "ovs-appctl doca/log-get" \
        "ovs-appctl doca/log-set error" \
        "ovs-appctl doca/log-set debug" ; do
        title "Command: $cmd"
        $cmd || err "Failed cmd: $cmd"
    done
}

misc_functions
test_done
