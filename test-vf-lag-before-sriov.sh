#!/bin/bash
#
# Test VF LAG still enabled and bond0 is still master over two uplinks
# before sriov and after switchdev mode is set.
# This test is checking the new uplink rep mode where uplink rep is not a new
# netdev device.
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module bonding

local_ip="2.2.2.2"
remote_ip="2.2.2.3"
dst_mac="e4:1d:2d:fd:8b:02"
dst_port=1234
id=98

function tc_filter() {
    eval2 tc filter $@ && success
}

function config_shared_block() {
    for i in bond0 $NIC $NIC2 ; do
        tc qdisc del dev $i ingress
        tc qdisc add dev $i ingress_block 22 ingress
    done
}

function config() {
    title "- config"
    config_sriov 0
    config_sriov 0 $NIC2
    config_bonding $NIC $NIC2
    fail_if_err
    title "- enable sriov"
    config_sriov 2
    config_sriov 2 $NIC2
    title "- set uplink rep mode"
    set_uplink_rep_mode_nic_netdev
    set_uplink_rep_mode_nic_netdev $NIC2
    title "- enable switchdev"
    enable_switchdev
    enable_switchdev $NIC2
    reset_tc $NIC $NIC2
    config_shared_block
    if [ $TEST_FAILED == 1 ]; then
        cleanup
    fi
    fail_if_err
}

function clean_shared_block() {
    for i in bond0 $NIC $NIC2 ; do
        tc qdisc del dev $i ingress_block 22 ingress &>/dev/null
    done
}

function cleanup() {
    clean_shared_block
    clear_bonding
    config_sriov 1
    config_sriov 1 $NIC2
    set_uplink_rep_mode_new_netdev
    set_uplink_rep_mode_new_netdev $NIC2
    config_sriov 0
    config_sriov 0 $NIC2
}

function verify_bond_master() {
    local nic
    local tmp

    title " - verify bond0 is still master"

    for nic in $NIC $NIC2 ; do
        tmp=$(basename `readlink -f /sys/class/net/$nic/master`)
        if [ "$tmp" != "bond0" ]; then
            err "$nic is not slaved to bond0"
        fi
    done
}

function verify_vf_lag() {
    title " - verify vf lag"
    ifconfig $NIC down
    ifconfig $NIC up
    if ! is_bonded ; then
        err "VF lag check failed"
    fi
}

trap cleanup EXIT
cleanup
config
verify_bond_master
verify_vf_lag
cleanup
test_done
