#!/bin/bash
#
# Basic add rules between SF REP and bond interface
#
# Bug SW #3531579: [BF2,Ubuntu20.04][VirtIO-net-VF] - Syndrome(0x35e4ff) occurs when sending traffic over BOND with VirtIO-VF

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-sf.sh

require_module bonding
require_interfaces NIC NIC2

local_ip="2.2.2.2"
remote_ip="2.2.2.3"
dst_mac="e4:1d:2d:fd:8b:02"
dst_port=1234
id=98

function config_shared_block() {
    for i in bond0 $NIC $NIC2 ; do
        tc qdisc del dev $i ingress
        tc qdisc add dev $i ingress_block 22 ingress || err "Failed to add ingress_block"
    done
}

function config() {
    config_sriov 2
    config_sriov 0 $NIC2
    enable_switchdev
    enable_switchdev $NIC2
    reset_tc $NIC $NIC2
    config_bonding $NIC $NIC2
    config_shared_block
}

function clean_shared_block() {
    for i in bond0 $NIC $NIC2 ; do
        tc qdisc del dev $i ingress_block 22 ingress &>/dev/null
    done
}

function cleanup() {
    clean_shared_block
    clear_bonding
    ifconfig $NIC down
}

function test_add_redirect_rule() {
    create_sfs 1
    reset_tc $SF_REP1

    title "- bond0 -> $SF_REP1"
    tc_filter_success add block 22 protocol arp parent ffff: prio 3 \
        flower dst_mac $dst_mac \
        action mirred egress redirect dev $SF_REP1
    verify_in_hw $NIC 3
    verify_in_hw $NIC2 3

    title "- $SF_REP1 -> bond0"
    tc_filter_success add dev $SF_REP1 protocol arp parent ffff: prio 3 \
        flower dst_mac $dst_mac skip_sw \
        action mirred egress redirect dev bond0

    reset_tc $SF_REP1
    remove_sfs
}

function do_cmd() {
    title $1
    eval $1
}

trap cleanup EXIT
cleanup
config
fail_if_err
do_cmd test_add_redirect_rule
trap - EXIT
cleanup
test_done
