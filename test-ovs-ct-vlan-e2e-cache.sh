#!/bin/bash
#
# Test OVS with vlan traffic
#
# Require external server
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
    ovs_conf_remove e2e-enable
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
    ovs_conf_set e2e-enable true

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
    zone=99
    ovs-ofctl del-flows br-ovs
    ovs-ofctl add-flow br-ovs arp,actions=normal
    ovs-ofctl add-flow br-ovs icmp,actions=normal
    ovs-ofctl add-flow br-ovs "table=0, ip,ct_state=-trk actions=ct(table=1,zone=$zone)"
    ovs-ofctl add-flow br-ovs "table=1, ip,ct_state=+trk+new actions=ct(zone=$zone, commit),normal"
    ovs-ofctl add-flow br-ovs "table=1, ip,ct_zone=$zone,ct_state=+trk+est actions=normal"
    ovs-ofctl dump-flows br-ovs --color
}

function e2e_cache_verify() {
    for i in $REP $NIC ; do
        title e2e_cache $i
        tc_filter show dev $i ingress e2e_cache
        tc_filter show dev $i ingress e2e_cache | grep -q handle
        if [ "$?" != 0 ]; then
            err "Expected e2e_cache rule"
        fi
    done
}

function run() {
    config
    config_remote
    add_openflow_rules

    # icmp
    ip netns exec ns0 ping -q -c 1 -w 1 $REMOTE
    if [ $? -ne 0 ]; then
        err "ping failed"
        return
    fi

    t=15
    # traffic
    ssh2 $REMOTE_SERVER timeout $((t+2)) iperf -s -t $t &
    pid1=$!
    sleep 2
    ip netns exec ns0 timeout $((t+2)) iperf -c $REMOTE -t $t -P3 &
    pid2=$!

    # verify pid
    sleep 2
    kill -0 $pid2 &>/dev/null
    if [ $? -ne 0 ]; then
        err "iperf failed"
        return
    fi

    e2e_cache_verify

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
reset_tc $NIC $REP
test_done
