#!/bin/bash
#
# Test offloading on vxlan setup with VF as tunnel endpoint
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
    config_sriov 2
    enable_switchdev
    require_interfaces REP REP2 NIC
    unbind_vfs
    bind_vfs

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
    local filter="$1"
    local t=5

    echo "sniff packets on $VF"
    timeout $t tcpdump -qnnei $VF -c 4 "$filter" &
    tpid=$!
    sleep 0.5

    echo "run ping for $t seconds"
    ip netns exec ns0 ping -I $VF2 $REMOTE_VF_IP -c $t -w $t -q &
    ppid=$!
    sleep 0.5

    echo "sniff packets on $REP2"
    timeout $t tcpdump -qnnei $REP2 -c 3 -Q in icmp &
    tpid2=$!

    wait $ppid &>/dev/null
    [ $? -ne 0 ] && err "Ping failed" && return 1

    title "test traffic on $VF"
    verify_no_traffic $tpid
    title "test traffic on $REP2"
    verify_no_traffic $tpid2
}


title "Test IPv4 tunnel"
cleanup
config $LOCAL_IP $REMOTE_IP 24
# VXLAN IPv4 encap with payload ethertype=IPv4
run "port 4789 and udp[8:2] = 0x0800 & 0x0800 and udp[11:4] = 98 & 0x00FFFFFF and udp[28:2] = 0x0800"

title "Test IPv6 tunnel"
cleanup
config $LOCAL_IPV6 $REMOTE_IPV6 64
# VXLAN IPv6 encap with payload ethertype=IPv4
run "port 4789 and ip6[48:2] = 0x0800 & 0x0800 and ip6[51:4] = 98 & 0x00FFFFFF and ip6[68:2] = 0x0800"

cleanup
trap - EXIT
test_done
