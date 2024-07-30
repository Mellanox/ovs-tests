#!/bin/bash
#
# Test LLDP traffic goes to kernel
# Min FW XX.42.0344.
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

PCAP="/tmp/out.pcap"

require_remote_server

config_sriov 2
enable_switchdev

trap cleanup_test EXIT

function config() {
    cleanup_test

    config_simple_bridge_with_rep 2
}

function run() {
    config

    title "Check lldp from remote"
    echo "Start tcpdump on $NIC"
    timeout 10 tcpdump -nnei $NIC -c 10 ether proto 0x88cc &
    local pid=$!

    on_remote "ifconfig $REMOTE_NIC up"
    on_remote "python -c \"from scapy.all import *; p=Ether(dst='01:80:c2:00:00:0e', type=0x88cc); sendp(p, iface='$REMOTE_NIC', count=10, inter=0.5)\""
    wait $pid
    local rc=$?
    if [ "$rc" -eq 0 ]; then
        success
    elif [ "$rc" -eq 124 ]; then
        err "lldp traffic didn't reach uplink"
    else
        err "tcpdump err $rc"
    fi
}

run
trap - EXIT
cleanup_test
test_done
