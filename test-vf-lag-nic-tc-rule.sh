#!/bin/bash
#
# Test creates TC rule on shared block connected to both PFs that are enslaved
# by bond device. It verifies both that such rule can be created without
# crashing and that it has proper in hardware count.
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module bonding

function config_shared_block() {
    for i in bond0 $NIC $NIC2 ; do
        tc qdisc del dev $i ingress
        tc qdisc add dev $i ingress_block 22 ingress || err "Failed to add ingress_block"
    done
}

function config() {
    title "- config"
    disable_sriov
    config_bonding $NIC $NIC2
    fail_if_err
    reset_tc $NIC $NIC2
    ethtool_hw_tc_offload $NIC
    ethtool_hw_tc_offload $NIC2
    config_shared_block
    if [ $TEST_FAILED == 1 ]; then
        cleanup
    fi
    fail_if_err
}

function tc_create_filter() {
    tc_filter_success add block 22 protocol ip \
                      flower src_ip 10.37.67.205 dst_ip 10.39.2.57 ip_proto udp dst_port 4789 \
                      action drop
    verify_in_hw_count $NIC 2
}

function clean_shared_block() {
    for i in bond0 $NIC $NIC2 ; do
        tc qdisc del dev $i ingress_block 22 ingress &>/dev/null
    done
}

function cleanup() {
    clean_shared_block
    clear_bonding
    disable_sriov
}

trap cleanup EXIT
cleanup
config
tc_create_filter
cleanup
test_done
