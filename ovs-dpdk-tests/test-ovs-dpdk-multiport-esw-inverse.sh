#!/bin/bash

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

trap cleanup EXIT

function cleanup() {
    title "Cleanup"
    cleanup_mpesw
    cleanup_test
    set_grace_period $grace_period
}

function config_ovs() {
    local bridge="br-phy"
    REP2=`get_rep 0 $NIC2`

    ovs_add_bridge $bridge
    ovs_add_dpdk_port $bridge $NIC
    ovs_add_dpdk_port $bridge $NIC2

    ovs_add_dpdk_port $bridge $REP
    ovs_add_dpdk_port $bridge $REP2
}

function config_ips() {
    local pf1vf0=`get_vf 0 $NIC2`

    ip a flush dev $VF
    ip a add $LOCAL_IP2/24 dev $VF
    ip a flush dev $pf1vf0
    ip a add $LOCAL_IP/24 dev $pf1vf0
}

function set_interfaces_up() {
    local pf1vf0=`get_vf 0 $NIC2`

    ip link set $NIC up
    ip link set $NIC2 up
    ip link set $VF up
    ip link set $pf1vf0 up
}

function config_remote_ips() {
    on_remote "ip a flush dev $REMOTE_NIC
               ip a add $REMOTE_IP/24 dev $REMOTE_NIC
               ip l set dev $REMOTE_NIC up
               ip a flush dev $REMOTE_NIC2
               ip a add $REMOTE_IP2/24 dev $REMOTE_NIC2
               ip l set dev $REMOTE_NIC2 up"
}

function config() {
    title "Config"
    set_grace_period 0
    config_mpesw
    config_ovs
    config_ips
    config_remote_ips
}

function run() {
    config

    verify_ping $REMOTE_IP none 56 10
    verify_ping $REMOTE_IP2 none 56 10

    generate_traffic local $REMOTE_IP none true none remote
    generate_traffic local $REMOTE_IP2 none true none remote
}

get_grace_period
run
trap - EXIT
cleanup
test_done
