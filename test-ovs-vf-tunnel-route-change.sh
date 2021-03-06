#!/bin/bash
#
# Test offloading on vxlan setup with VF as tunnel endpoint and concurrent route
# change.
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

REMOTE_SERVER=${REMOTE_SERVER:-$1}
REMOTE_NIC=${REMOTE_NIC:-$2}

require_remote_server
not_relevant_for_nic cx4 cx4lx cx5

LOCAL_IP="7.7.7.5"
REMOTE_IP="7.7.7.1"
LOCAL_IPV6="2001:0db8:0:f101::1"
REMOTE_IPV6="2001:0db8:0:f101::2"
VF_IP="5.5.5.5"
REMOTE_VF_IP="5.5.5.1"

function __cleanup() {
    local local_ip=$1
    local remote_ip=$2
    local subnet=$3

    ip addr del $local_ip/$subnet dev $VF &>/dev/null
    ip netns del ns0 &>/dev/null
    start_clean_openvswitch

    on_remote "\
        ip link del vxlan0 type vxlan &>/dev/null;\
        ip addr del $remote_ip/$subnet dev $REMOTE_NIC &>/dev/null"
}

function cleanup() {
    __cleanup $LOCAL_IP $REMOTE_IP 24
    __cleanup $LOCAL_IPV6 $REMOTE_IPV6 64
}
trap cleanup EXIT

function config() {
    local local_ip=$1
    local remote_ip=$2
    local subnet=$3

    title "Config local host"
    config_sriov 3
    enable_switchdev
    REP3=`get_rep 2`
    require_interfaces REP REP2 REP3 NIC
    unbind_vfs
    bind_vfs
    VF3=`get_vf 2`
    reset_tc $REP
    reset_tc $REP2

    ip a add dev $VF $local_ip/$subnet
    ip link set dev $VF up
    config_vf ns0 $VF2 $REP2 $VF_IP 24
    ip addr flush dev $NIC
    ip link set dev $NIC up

    start_clean_openvswitch
    ovs-vsctl add-br ovs-br
    ovs-vsctl add-port ovs-br $NIC
    ovs-vsctl add-port ovs-br $REP
    ovs-vsctl add-port ovs-br $REP2
    ovs-vsctl add-port ovs-br $REP3
    ovs-vsctl add-port ovs-br vxlan0 \
        -- set interface vxlan0 type=vxlan \
            options:remote_ip=$remote_ip \
            options:local_ip=$local_ip \
            options:key=98 options:dst_port=4789;

    title "Config remote host"
    remote_disable_sriov
    on_remote "\
        ip link add vxlan0 type vxlan id 98 dev $REMOTE_NIC local $remote_ip dstport 4789 udp6zerocsumrx;\
        ifconfig vxlan0 $REMOTE_VF_IP/24 up;\
        ip link set vxlan0 addr 0a:40:bd:30:89:99;\
        ip addr add $remote_ip/$subnet dev $REMOTE_NIC;\
        ip link set $REMOTE_NIC up"

    sleep 1
}

function run() {
    local local_ip=$1
    local subnet=$2
    local stack_vf1=$3
    local stack_vf2=$4
    local t=3
    local vxlan_netdev="vxlan_sys_4789"

    echo "run ping for $t seconds"
    ip netns exec ns0 ping -I $VF2 $REMOTE_VF_IP -w $t || err "Ping failed"

    ip a del $local_ip/$subnet dev $stack_vf1
    ip link set dev $stack_vf2 up
    ip a add dev $stack_vf2 $local_ip/$subnet
    sleep 2

    echo "sniff packets on $vxlan_netdev"
    timeout $t tcpdump -qnnei $vxlan_netdev -c 2 -Q in icmp &
    tpid=$!
    sleep 1

    ip netns exec ns0 ping -I $VF2 $REMOTE_VF_IP -c $t -w $t || err "Ping failed"

    title "test traffic on $vxlan_netdev"
    verify_no_traffic $tpid
}


title "Test IPv4 tunnel"
cleanup
config $LOCAL_IP $REMOTE_IP 24
run $LOCAL_IP 24 $VF $VF3

title "Test IPv6 tunnel"
cleanup
config $LOCAL_IPV6 $REMOTE_IPV6 64
run $LOCAL_IPV6 64 $VF $VF3

cleanup
trap - EXIT
test_done
