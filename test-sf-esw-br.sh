#!/bin/bash
#
# Test adding SF ESW to a Linux bridge.

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-sf.sh

IP1="7.7.7.1"
IP2="7.7.7.2"

function cleanup() {
    log "cleanup"
    ip netns exec ns0 brctl delbr bb1
    reset_sfs_ns
    remove_sfs
}

trap cleanup EXIT

function config() {
    title "Config"
    create_sfs 1

    set_sf_eswitch
    reload_sfs_into_ns
    set_sf_switchdev

    title "Add SF to bridge"
    ip netns exec ns0 brctl addbr bb1
    ip netns exec ns0 ip link set dev bb1 type bridge
    ip netns exec ns0 ip link set dev bb1 type bridge vlan_filtering 1
    ip netns exec ns0 ip link set dev eth0 master bb1 || err "Failed to add SF to bridge"
}

enable_switchdev
config
trap - EXIT
cleanup
test_done
