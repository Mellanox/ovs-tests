#!/bin/bash
#
# Test inserting mirror rules over vf lag with 32 destinations
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

function config_shared_block() {
    for i in bond0 $NIC $NIC2 ; do
        tc qdisc del dev $i ingress
        tc qdisc add dev $i ingress_block 22 ingress || err "Failed to add ingress_block"
    done
}

function clean_shared_block() {
    for i in bond0 $NIC $NIC2 ; do
        tc qdisc del dev $i ingress_block 22 ingress &>/dev/null
    done
}

disable_sriov_autoprobe
config_sriov 16
config_sriov 16 $NIC2
enable_switchdev
enable_switchdev $NIC2
sleep 2
config_bonding $NIC $NIC2
config_shared_block

function cleanup() {
    clean_shared_block
    restore_sriov_autoprobe
}

trap cleanup EXIT

function test_32_dest() {
    title "Add mirror rule on block qdisc with 32 dst"
    tc_filter del block 22 ingress
    command="tc_filter_success add block 22 ingress protocol arp prio 1 flower "
    for i in {0..14}
    do
        TMP_REP=`get_rep $i`
        command+=" action mirred egress mirror dev $TMP_REP pipe"
        TMP_REP=`get_rep $i $NIC2`
        command+=" action mirred egress mirror dev $TMP_REP pipe"
    done
    TMP_REP=`get_rep 15`
    command+=" action mirred egress mirror dev $TMP_REP"
    TMP_REP=`get_rep 15 $NIC2`
    command+=" action mirred egress redirect dev $TMP_REP"
    eval $command
    tc_filter del block 22 ingress
}

test_32_dest
check_kasan
clear_bonding
config_sriov 2
config_sriov 2 $NIC2
test_done
