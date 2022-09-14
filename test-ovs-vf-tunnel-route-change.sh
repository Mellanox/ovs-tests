#!/bin/bash
#
# Test offloading on vxlan setup with VF as tunnel endpoint and concurrent route
# change.
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

min_nic_cx6
require_remote_server

LOCAL_IP="7.7.7.5"
REMOTE_IP="7.7.7.1"
LOCAL_IPV6="2001:0db8:0:f101::1"
REMOTE_IPV6="2001:0db8:0:f101::2"
VF_IP="5.5.5.5"
REMOTE_VF_IP="5.5.5.1"

function cleanup() {
    ip addr flush dev $VF &>/dev/null
    ip addr flush dev $VF3 &>/dev/null
    ip -netns ns0 link set dev $VF2 netns 1 2>/dev/null
    ip -all netns delete
    start_clean_openvswitch
    cleanup_remote_vxlan
}
trap cleanup EXIT

function config() {
    local local_ip=$1
    local remote_ip=$2
    local subnet=$3

    title "Config local host"

    ip a add dev $VF $local_ip/$subnet
    ip link set dev $VF up
    config_vf ns0 $VF2 $REP2 $VF_IP
    ip addr flush dev $NIC
    ip link set dev $NIC up
    ip link set dev $REP up
    ip link set dev $REP2 up
    ip link set dev $REP3 up

    ovs-vsctl add-br ovs-br
    ovs-vsctl add-port ovs-br $NIC
    ovs-vsctl add-port ovs-br $REP
    ovs-vsctl add-port ovs-br $REP2
    ovs-vsctl add-port ovs-br $REP3
    ovs-vsctl add-port ovs-br vxlan1 \
        -- set interface vxlan1 type=vxlan \
            options:remote_ip=$remote_ip \
            options:local_ip=$local_ip \
            options:key=98 options:dst_port=4789;

    title "Config remote host"
    on_remote "ip link add vxlan1 type vxlan id 98 dev $REMOTE_NIC local $remote_ip dstport 4789 udp6zerocsumrx
               ifconfig vxlan1 $REMOTE_VF_IP/24 up
               ip link set vxlan1 addr 0a:40:bd:30:89:99
               ip addr add $remote_ip/$subnet dev $REMOTE_NIC
               ip link set $REMOTE_NIC up"

    sleep 1
}

function run() {
    local local_ip=$1
    local subnet=$2
    local stack_vf1=$3
    local stack_vf2=$4
    local t=5
    local vxlan_netdev="vxlan_sys_4789"

    title "Test first ping over stack dev $stack_vf1"
    ip netns exec ns0 ping -I $VF2 $REMOTE_VF_IP -w $t || err "First ping failed"

    ip a del $local_ip/$subnet dev $stack_vf1
    ip link set dev $stack_vf2 up
    ip a add dev $stack_vf2 $local_ip/$subnet
    sleep 2

    echo "sniff packets on $vxlan_netdev"
    timeout $t tcpdump -qnnei $vxlan_netdev -c 3 -Q in icmp &
    tpid=$!
    sleep 1

    title "Test second ping over stack dev $stack_vf2"
    ip netns exec ns0 ping -I $VF2 $REMOTE_VF_IP -c $t -w $t || err "Second ping failed"

    title "Test offload on $vxlan_netdev"
    verify_no_traffic $tpid
}

config_sriov 3
enable_switchdev
REP3=`get_rep 2`
require_interfaces REP REP2 REP3 NIC
unbind_vfs
bind_vfs
VF3=`get_vf 2`
remote_disable_sriov
cleanup

title "Test IPv4 tunnel"
config $LOCAL_IP $REMOTE_IP 24
run $LOCAL_IP 24 $VF $VF3
cleanup

title "Test IPv6 tunnel"
config $LOCAL_IPV6 $REMOTE_IPV6 64
run $LOCAL_IPV6 64 $VF $VF3
cleanup

trap - EXIT
test_done
