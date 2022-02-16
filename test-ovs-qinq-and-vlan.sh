#!/bin/bash
#
# Test OVS with vlan traffic and qinq traffic at the same time
#
# Bug SW #2599393: Failed to pass offload on server side - packet count is 0 over QinQ
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_remote_server

IP=1.1.1.7
REMOTE=1.1.1.8
IP2=2.1.1.7
REMOTE2=2.1.1.8

in_vlan=5
out_vlan=10
out_vlan_dev=${REMOTE_NIC}.$out_vlan
in_vlan_dev=${out_vlan_dev}.$in_vlan

config_sriov 2
enable_switchdev
require_interfaces REP NIC
unbind_vfs
bind_vfs


function cleanup_remote() {
    on_remote ip a flush dev $REMOTE_NIC
    on_remote ip l del dev $in_vlan_dev &>/dev/null
    on_remote ip l del dev $out_vlan_dev &>/dev/null
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
    ip netns exec ns0 ip link add link $VF name $VF.$in_vlan type vlan id $in_vlan
    ip netns exec ns0 ifconfig $VF $IP/24 up
    ip netns exec ns0 ifconfig $VF.$in_vlan $IP2/24 up

    echo "Restarting OVS"
    start_clean_openvswitch
    ovs-vsctl set Open_vSwitch . other_config:vlan-limit=2
    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP tag=$out_vlan vlan-mode=dot1q-tunnel other-config:qinq-ethtype=802.1q
    ovs-vsctl add-port br-ovs $NIC
}

function config_remote() {
    on_remote "ip a flush dev $REMOTE_NIC
               ip l set dev $REMOTE_NIC up
               ip link add link $REMOTE_NIC name $out_vlan_dev type vlan id $out_vlan
               ip link add link $out_vlan_dev name $in_vlan_dev type vlan id $in_vlan
               ip a add $REMOTE/24 dev $out_vlan_dev
               ip l set dev $out_vlan_dev up
               ip a add $REMOTE2/24 dev $in_vlan_dev
               ip l set dev $in_vlan_dev up"
}

function add_openflow_rules() {
#    ovs-ofctl del-flows br-ovs
#    ovs-ofctl add-flow br-ovs arp,actions=normal
#    ovs-ofctl add-flow br-ovs icmp,actions=normal
    ovs-ofctl dump-flows br-ovs --color
}

function check_offloaded_rules() {
    local count=$1
    title " - check for $count offloaded rules"
    RES="ovs_dump_tc_flows | grep 0x0800 | grep -v drop"
    eval $RES
    RES=`eval $RES | wc -l`
    if (( RES == $count )); then success; else err; fi
}

function run() {
    config
    config_remote
    add_openflow_rules

    # icmp
    ip netns exec ns0 ping  -c 30 $REMOTE &

    sleep 1

    ip netns exec ns0 ping  -c 30 $REMOTE2 &

    sleep 3

    check_offloaded_rules 4

    killall -9 -q ping
    echo "wait for bgs"
    wait
}

run
start_clean_openvswitch
test_done
