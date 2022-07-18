#!/bin/bash
#
# Test basic CT functionality over stacked devices topology.
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

min_nic_cx6
require_remote_server

LOCAL_IP="7.7.7.5"
REMOTE_IP="7.7.7.1"
VF_IP="5.5.5.5"
VF_MAC="0a:40:bd:30:89:9a"
REMOTE_VXLAN_DEV_IP="5.5.5.1"
REMOTE_VXLAN_DEV_MAC="0a:40:bd:30:89:99"
VXLAN_PORT=vxlan0

function __cleanup() {
    local local_ip=$1
    local remote_ip=$2
    local subnet=$3

    ip addr del $local_ip/$subnet dev $VF &>/dev/null
    ip netns del ns0 &>/dev/null
    start_clean_openvswitch

    on_remote "ip link del vxlan0 type vxlan &>/dev/null
               ip addr del $remote_ip/$subnet dev $REMOTE_NIC &>/dev/null"
}

function cleanup() {
    __cleanup $LOCAL_IP $REMOTE_IP 24
}
trap cleanup EXIT

function ovs-ofctl1 {
    local ofctl_err=0
    ovs-ofctl $@ || ofctl_err=1
    if [ $ofctl_err -ne 0 ]; then
        err "Command failed: ovs-ofctl $@"
    fi
}

function config_ovs_ct() {
    ovs-ofctl1 del-flows ovs-br
    ovs-ofctl1 add-flow ovs-br "arp,action=normal"
    ovs-ofctl1 add-flow ovs-br "udp,action=normal"
    ovs-ofctl1 add-flow ovs-br "icmp,action=normal"

    ovs-ofctl1 add-flow ovs-br -O openflow13 "table=0,in_port=$VM1_PORT,ip,tcp,action=ct(table=1,zone=5)"
    ovs-ofctl1 add-flow ovs-br -O openflow13 "table=0,in_port=$VM2_PORT,ip,tcp,ct_state=-trk,ip,action=ct(table=1,zone=5)"

    ovs-ofctl1 add-flow ovs-br -O openflow13 "table=1,in_port=$VM1_PORT,ip,tcp,ct_state=+trk+new,ct_zone=5,ip,action=ct(commit,zone=5),$VM2_PORT"
    ovs-ofctl1 add-flow ovs-br -O openflow13 "table=1,in_port=$VM1_PORT,ip,tcp,ct_state=+trk+est,ct_zone=5,ip,action=$VM2_PORT"
    ovs-ofctl1 add-flow ovs-br -O openflow13 "table=1,in_port=$VM2_PORT,ip,tcp,ct_state=+trk+est,ct_zone=5,ip,action=$VM1_PORT"

    ovs-ofctl1 add-flow ovs-br -O openflow13 "table=1,in_port=$VM2_PORT,ip,tcp,ct_state=+trk+new,ct_zone=5,ip,action=ct(commit,zone=5),$VM1_PORT"
    fail_if_err "Failed to set ofctl rules"
}

function config_ovs() {
    echo "setup ovs"
    start_clean_openvswitch
    ovs-vsctl add-br ovs-br
    ovs-vsctl add-port ovs-br $NIC
    ovs-vsctl add-port ovs-br $REP
    ovs-vsctl add-port ovs-br $REP2
    ovs-vsctl add-port ovs-br $VXLAN_PORT \
              -- set interface $VXLAN_PORT type=vxlan \
              options:remote_ip=$remote_ip \
              options:local_ip=$local_ip \
              options:key=98 options:dst_port=4789;

    VM1_PORT=`ovs-vsctl list interface $VXLAN_PORT | grep "ofport\s*:" | awk {'print $3'}`
    VM2_PORT=`ovs-vsctl list interface $REP2 | grep "ofport\s*:" | awk {'print $3'}`

    config_ovs_ct
    ovs-ofctl dump-flows ovs-br --color
}

function config() {
    local local_ip=$1
    local remote_ip=$2
    local subnet=$3

    title "Config local host"
    config_sriov 2
    enable_switchdev
    require_interfaces REP REP2 NIC
    unbind_vfs
    bind_vfs

    ip a add dev $VF $local_ip/$subnet
    ip link set dev $VF up
    config_vf ns0 $VF2 $REP2 $VF_IP
    ip -netns ns0 link set $VF2 addr $VF_MAC
    ip -netns ns0 neigh replace $REMOTE_VXLAN_DEV_IP dev $VF2 lladdr $REMOTE_VXLAN_DEV_MAC
    ip addr flush dev $NIC
    ip link set dev $NIC up
    ip link set dev $REP up

    config_ovs

    title "Config remote host"
    remote_disable_sriov
    on_remote "ip link add vxlan0 type vxlan id 98 dev $REMOTE_NIC local $remote_ip dstport 4789 udp6zerocsumrx
               ifconfig vxlan0 $REMOTE_VXLAN_DEV_IP/24 up
               ip link set vxlan0 addr $REMOTE_VXLAN_DEV_MAC
               ip neigh replace $VF_IP dev vxlan0 lladdr $VF_MAC
               ip addr add $remote_ip/$subnet dev $REMOTE_NIC
               ip link set $REMOTE_NIC up"

    sleep 1
}

function run() {
    t=15

    ovs-ofctl dump-flows ovs-br --color

    # traffic
    on_remote timeout $((t+2)) iperf -s -t $t &
    pid1=$!
    sleep 2
    ip netns exec ns0 timeout $((t+2)) iperf -c $REMOTE_VXLAN_DEV_IP -t $t -P3 &
    pid2=$!

    # verify pid
    sleep 2
    kill -0 $pid2 &>/dev/null
    if [ $? -ne 0 ]; then
        err "iperf failed"
        return
    fi

    timeout $((t-2)) tcpdump -qnnei $REP -c 10 'udp' &
    tpid=$!
    timeout $((t-2)) tcpdump -qnnei vxlan_sys_4789 -c 10 &
    tpid1=$!
    sleep $t

    title "Verify offload on $REP"
    verify_no_traffic $tpid
    title "Verify offload on vxlan_sys_4789"
    verify_no_traffic $tpid1

    kill -9 $pid1 &>/dev/null
    killall iperf &>/dev/null
    echo "wait for bgs"
    wait
}


title "Test IPv4 tunnel"
cleanup
config $LOCAL_IP $REMOTE_IP 24

run

cleanup
trap - EXIT
test_done
