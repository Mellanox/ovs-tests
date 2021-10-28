#!/bin/bash
#
# Test OVS-DPDK with vxlan TCP traffic with CT
#
# E2E-CACHE
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/../common.sh
. $my_dir/common-dpdk.sh

require_remote_server

IP=1.1.1.7
REMOTE=1.1.1.8

LOCAL_TUN=7.7.7.7
REMOTE_IP=7.7.7.8
VXLAN_ID=42

config_sriov 2
enable_switchdev
require_interfaces REP NIC
unbind_vfs
bind_vfs


function cleanup_remote() {
    on_remote ip a flush dev $REMOTE_NIC
    on_remote ip l del dev vxlan1 &>/dev/null
}

function cleanup() {
    ip a flush dev $NIC
    ip netns del ns0 &>/dev/null
    cleanup_e2e_cache
    cleanup_remote
    sleep 0.5
}
trap cleanup EXIT

function config() {
    cleanup
    set_e2e_cache_enable true
    echo "Restarting OVS"
    start_clean_openvswitch

    config_simple_bridge_with_rep 0
    config_remote_bridge_tunnel $VXLAN_ID $REMOTE_IP
    config_local_tunnel_ip $LOCAL_TUN br-phy
    config_ns ns0 $VF $IP
}

function config_remote() {
    on_remote ip link del vxlan1 &>/dev/null
    on_remote ip link add vxlan1 type vxlan id $VXLAN_ID remote $LOCAL_TUN dstport 4789
    on_remote ip a flush dev $REMOTE_NIC
    on_remote ip a add $REMOTE_IP/24 dev $REMOTE_NIC
    on_remote ip a add $REMOTE/24 dev vxlan1
    on_remote ip l set dev vxlan1 up
    on_remote ip l set dev $REMOTE_NIC up
}

function add_openflow_rules() {
    ovs-ofctl del-flows br-int
    ovs-ofctl add-flow br-int "arp,actions=NORMAL"
    ovs-ofctl add-flow br-int "table=0,tcp,ct_state=-trk,actions=ct(zone=5, table=1)"
    ovs-ofctl add-flow br-int "table=1,tcp,ct_state=+trk+new,actions=ct(zone=5, commit),NORMAL"
    ovs-ofctl add-flow br-int "table=1,tcp,ct_state=+trk+est,ct_zone=5,actions=normal"
    echo -e "\nOVS flow rules:"
    ovs-ofctl dump-flows br-int --color
}

function run() {
    config
    config_remote
    add_openflow_rules

    echo -e "\nTesting TCP traffic"
    t=15
    # traffic
    ip netns exec ns0 timeout $((t+2)) iperf3 -s &
    pid1=$!
    sleep 2
    on_remote timeout $((t+2)) iperf3 -c $IP -t $t -P 10&
    pid2=$!

    # verify pid
    sleep 5
    kill -0 $pid2 &>/dev/null
    if [ $? -ne 0 ]; then
        err "iperf3 failed"
        return
    fi

    kill -9 $pid1 &>/dev/null
    killall iperf3 &>/dev/null
    echo "wait for bgs"
    wait

    check_e2e_stats 20
}

run
start_clean_openvswitch
test_done
