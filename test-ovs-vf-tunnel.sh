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
not_relevant_for_cx4
not_relevant_for_cx4lx
not_relevant_for_cx5

LOCAL_IP="7.7.7.5"
REMOTE_IP="7.7.7.1"
VF_IP="5.5.5.5"
REMOTE_VF_IP="5.5.5.1"

function cleanup() {
    ip addr del $LOCAL_IP/24 dev $VF &>/dev/null
    ip netns del ns0 &>/dev/null
    start_clean_openvswitch

    on_remote "\
        ip link del vxlan0 type vxlan &>/dev/null;\
        ip addr del $REMOTE_IP/24 dev $REMOTE_NIC &>/dev/null"
}
trap cleanup EXIT

function config() {
    title "Config local host"
    config_sriov 2
    enable_switchdev
    require_interfaces REP REP2 NIC
    unbind_vfs
    bind_vfs

    ifconfig $VF $LOCAL_IP/24 up
    config_vf ns0 $VF2 $REP2 $VF_IP 24
    start_clean_openvswitch
    ovs-vsctl add-br ovs-br
    ovs-vsctl add-port ovs-br $NIC
    ovs-vsctl add-port ovs-br $REP
    ovs-vsctl add-port ovs-br $REP2
    ovs-vsctl add-port ovs-br vxlan0 \
        -- set interface vxlan0 type=vxlan \
            options:remote_ip=$REMOTE_IP \
            options:local_ip=$LOCAL_IP \
            options:key=98 options:dst_port=4789;

    title "Config remote host"
    remote_disable_sriov
    on_remote "\
        ip link add vxlan0 type vxlan id 98 dev $REMOTE_NIC local $REMOTE_IP dstport 4789;\
        ifconfig vxlan0 $REMOTE_VF_IP/24 up;\
        ip link set vxlan0 addr 0a:40:bd:30:89:99;\
        ip addr add $REMOTE_IP/24 dev $REMOTE_NIC;\
        ip link set $REMOTE_NIC up"

    sleep 1
}

function run() {
    local t=5

    echo "sniff packets on $VF"
    timeout $t tcpdump -qnnei $VF -c 5 -Q in icmp &
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


cleanup
config
run

cleanup
trap - EXIT
test_done
