#!/bin/bash
#
# Test OVS with vxlan traffic with local mirroring and re-adding of a different
# mirror port with same port id
# Require external server
#
# Bug SW #4111668: [NGN] [CX6DX] [OVS-DOCA] Port-mirroring breaks the offload in pod2service use-case
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

config_sriov 3
enable_switchdev
bind_vfs

trap cleanup_test EXIT

function config() {
    cleanup_test

    config_tunnel "vxlan"
    config_remote_tunnel "vxlan"
    config_local_tunnel_ip $LOCAL_TUN_IP br-phy
}

function run() {
    local br="br-int"
    local VF3=`get_vf 2`

    config
    ifconfig $VF2 0 up
    ifconfig $VF3 0 up

    add_local_mirror mirror1 1 $br

    verify_ping $REMOTE_IP ns0
    generate_traffic "remote" $LOCAL_IP

    title "Replace $VF3 with $VF2 as mirror"
    ovs-vsctl clear bridge $br mirrors
    ovs-vsctl del-port mirror1

    sleep 5

    add_local_mirror mirror2 2 $br

    timeout 10 tcpdump -nnei $VF2 -S -c 5 host $LOCAL_IP &
    local pid_vf2_tcpdump=$!
    timeout 10 tcpdump -nnei $VF3 -S -c 5 host $LOCAL_IP &
    local pid_vf3_tcpdump=$!

    verify_ping $REMOTE_IP ns0
    generate_traffic "remote" $LOCAL_IP

    title "Verify tcpdump on VFs"
    wait $pid_vf2_tcpdump && err "Not expecting packets on $VF2"
    wait $pid_vf3_tcpdump || err "Expecting packets on $VF3"
}

run
trap - EXIT
cleanup_test
test_done
