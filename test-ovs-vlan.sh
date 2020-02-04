#!/bin/bash
#
# Test OVS with vlan traffic
#
# Require external server
#
# IGNORE_FROM_TEST_ALL

my_dir="$(dirname "$0")"
. $my_dir/common.sh

REMOTE_SERVER=${1:?Require remote server}
REMOTE_NIC=${2:?ens1f0}

require_remote_server

IP=1.1.1.7
REMOTE=1.1.1.8

vlan=5
vlan_dev=${REMOTE_NIC}.$vlan

config_sriov 2
enable_switchdev_if_no_rep $REP
require_interfaces REP NIC
unbind_vfs
bind_vfs


function cleanup_remote() {
    on_remote ip a flush dev $REMOTE_NIC
    on_remote ip l del dev vlan_dev &>/dev/null
}

function cleanup() {
    ip a flush dev $NIC
    ip netns del ns0 &>/dev/null
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
    ovs-vsctl add-port br-ovs $REP tag=$vlan
    ovs-vsctl add-port br-ovs $NIC
}

function config_remote() {
    on_remote "\
        ip a flush dev $REMOTE_NIC;\
        ip link add link $REMOTE_NIC name $vlan_dev type vlan id $vlan;\
        ip a add $REMOTE/24 dev $vlan_dev;\
        ip l set dev $vlan_dev up"
}

function add_openflow_rules() {
#    ovs-ofctl del-flows br-ovs
#    ovs-ofctl add-flow br-ovs arp,actions=normal
#    ovs-ofctl add-flow br-ovs icmp,actions=normal
    ovs-ofctl dump-flows br-ovs --color
}

function test_tcpdump() {
    local pid=$1
    wait $pid
    local rc=$?
    if [[ $rc -eq 124 ]]; then
        :
    elif [[ $rc -eq 0 ]]; then
        err "Didn't expect to see packets"
    else
        err "Tcpdump failed"
    fi
}

function run() {
    config
    config_remote
    add_openflow_rules

    # icmp
    ip netns exec ns0 ping -q -c 1 -i 0.1 -w 1 $REMOTE
    if [ $? -ne 0 ]; then
        err "ping failed"
    echo pause
    read
        return
    fi

    t=15
    # traffic
    ssh2 $REMOTE_SERVER timeout $((t+2)) iperf -s -t $t &
    pid1=$!
    sleep 0.5
    ip netns exec ns0 timeout $((t+2)) iperf -c $REMOTE -t $t -P3 &
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
    test_tcpdump $tpid

    kill -9 $pid1 &>/dev/null
    killall iperf &>/dev/null
    echo "wait for bgs"
    wait
}

run
start_clean_openvswitch
test_done
