#!/bin/bash
#
# Test OVS with implicit vlan traffic
#
# Require external server
#
# Bug SW #2115286: [Upstream] Sanity traffic is not passing over vlan
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

REMOTE_SERVER=${REMOTE_SERVER:-$1}
REMOTE_NIC=${REMOTE_NIC:-$2}

require_remote_server

IP=1.1.1.7
REMOTE=1.1.1.8

vlan=5
vlan_dev=${REMOTE_NIC}.$vlan

config_sriov 2
enable_switchdev
require_interfaces REP NIC
unbind_vfs
bind_vfs

function cleanup_remote() {
    on_remote ip a flush dev $REMOTE_NIC
    on_remote ip l del dev $vlan_dev &>/dev/null
}

function cleanup() {
    ip a flush dev $NIC
    ip netns del ns0 &>/dev/null
    ip l del dev $vlan_dev &>/dev/null
    cleanup_remote
    sleep 0.5
}
trap cleanup EXIT

function config() {
    cleanup
    # WA SimX bug? interface not receiving traffic from tap device to down&up to fix it.
    for i in $NIC $VF $REP ; do
            ifconfig $i down
            ifconfig $i up
            reset_tc $i
    done
    ip netns add ns0
    ip link set dev $VF netns ns0
    ip netns exec ns0 ifconfig $VF $IP/24 up

    echo "Restarting OVS"
    start_clean_openvswitch

    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ip l set dev $NIC up
    ip l set dev $REP up

    ip link add link $NIC name $vlan_dev type vlan id $vlan
    ip l set dev $vlan_dev up
    ovs-vsctl add-port br-ovs $vlan_dev
}

function config_remote() {
    on_remote "\
        ip a flush dev $REMOTE_NIC;\
        ip link add link $REMOTE_NIC name $vlan_dev type vlan id $vlan;\
        ip a add $REMOTE/24 dev $vlan_dev;\
        ip l set dev $NIC up;\
        ip l set dev $vlan_dev up;\
        "
}

function run() {
    config
    config_remote

    # icmp
    ip netns exec ns0 ping -q -c 10 -i 0.1 $REMOTE
    if [ $? -ne 0 ]; then
        err "ping failed"
        return
    fi

    t=15
    # traffic
    ip netns exec ns0 timeout $((t+2)) iperf -s -t $t &
    pid1=$!
    sleep 1
    on_remote timeout $((t+2)) iperf -c $IP -t $t -P3 &
    pid2=$!

    # verify pid
    sleep 2
    kill -0 $pid2 &>/dev/null
    if [ $? -ne 0 ]; then
        err "iperf failed"
        return
    fi

    timeout $((t-2)) tcpdump -qnnei $REP -c 10 'tcp' &
    tpid=$!
    sleep $t
    verify_no_traffic $tpid

    kill -9 $pid1 &>/dev/null
    killall iperf &>/dev/null

    echo "wait for bgs"
    wait
}

run
start_clean_openvswitch
test_done
