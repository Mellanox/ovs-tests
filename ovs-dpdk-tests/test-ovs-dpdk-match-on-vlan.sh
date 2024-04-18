#!/bin/bash

# This test checks that ovs-doca do a match on vlan.
# The tests creates a VF and a vlan on top sending
# traffic from VF and Vlan in parallel will cause inserting
# two similar rules however one will have a vlan. Not matching
# on vlan in HW will lead to one rule stealing the traffic from
# the other rule since basically both rules have the same matcher.
# SW #3717735: [OVS-DOCA, DOCA2.6] Failed to pass offload on server side - packet count is 0 over Bond

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

config_sriov 2
enable_switchdev
bind_vfs
require_interfaces NIC NIC2

vlan_ip=2.2.2.1
remote_vlan_ip=2.2.2.2
vlan_dev="$VF.3458"

function config_vlans() {
    ip link add link $VF name $vlan_dev type vlan id 3458
    ip address flush $vlan_dev
    ip address add $vlan_ip/24 dev $vlan_dev
    ip link set $vlan_dev up

    on_remote "ip link add link $VF name $vlan_dev type vlan id 3458
               ip address flush $vlan_dev
               ip address add $remote_vlan_ip/24 dev $vlan_dev
               ip link set $vlan_dev up"
}

function set_vfs_ips() {
    ip address flush $VF
    ip addr add $LOCAL_IP/24 dev $VF
    ip link set $VF up
    on_remote "ip address flush $VF
               ip addr add $REMOTE_IP/24 dev $VF
               ip link set $VF up"
}

function config() {
    config_simple_bridge_with_rep 1
    on_remote_exec "cleanup_test ; config_simple_bridge_with_rep 1"
    set_vfs_ips
    config_vlans
}

function cleanup() {
    cleanup_test
    ip link del $vlan_dev >/dev/null
    ip address flush $VF
    remote_cleanup_test
    on_remote "ip link del $vlan_dev >/dev/null
               ip address flush $VF"
}

function run_traffic() {
    exec_dbg "ping $REMOTE_IP -i 0.1 -c 100 &"
    exec_dbg "ping $remote_vlan_ip -i 0.1 -c 100 &"
    wait `pidof ping`
}

function check_offload() {
    validate_offload $REMOTE_IP 50
    validate_offload $remote_vlan_ip 50
}

function run_test() {
    cleanup_test
    config
    run_traffic
    check_offload
}

trap cleanup EXIT
run_test
trap - EXIT
cleanup
test_done
