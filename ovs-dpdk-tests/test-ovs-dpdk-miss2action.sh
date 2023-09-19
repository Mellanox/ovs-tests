#!/bin/bash
#
# Test partial offload using miss2action
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

config_sriov 2
enable_switchdev
require_interfaces REP NIC
bind_vfs

trap cleanup_test EXIT

function config() {
    cleanup_test
    config_simple_bridge_with_rep 2
    bf_wrap "ip link add dev veth0 type veth peer name rep-veth0"
    ovs-vsctl add-port br-phy rep-veth0
    ifconfig rep-veth0 up
    config_ns ns0 $VF $LOCAL_IP
    config_ns ns1 veth0 $REMOTE_IP
    ovs-vsctl show
}

function validate_rules() {
    local x=$(ovs-appctl dpctl/dump-flows -m type=partially-offloaded | grep 'eth_type(0x0800)' | wc -l)
    if [ "$x" != "1" ]; then
        ovs-appctl dpctl/dump-flows -m type=partially-offloaded | grep 'eth_type(0x0800)'
        err "Expected to have 1 flow (vf->veth), have $x"
    fi
}

function run() {
    config

    verify_ping
    validate_rules
}

run
bf_wrap "ip link del rep-veth0"
trap - EXIT
cleanup_test
test_done
