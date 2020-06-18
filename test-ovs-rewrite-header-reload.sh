#!/bin/bash
#
# Test check OVS mac learning with header rewrite rule after reload.
# OVS fail to offload icmp replies, if arp entry exist, while it is ok,
# when entry not exist or entries were added manually.
#
# Bug SW #1932655: [Upstream] Rules are not offloaded after rewrite MAC
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

VF1_IP="7.7.7.1"
VF2_IP="7.7.7.2"
VF1_MAC="e4:11:22:33:44:50"
VF2_MAC="e4:11:22:33:44:51"
FAKE_MAC="aa:bb:cc:dd:ee:ff"
OVSBR="ovs-sriov1"

function cleanup() {
    echo "cleanup"
    start_clean_openvswitch
    ip netns del ns0 &> /dev/null
    ip netns del ns1 &> /dev/null
}

function create_namespace() {
    local ns=$1
    local rep=$2
    local vf=$3
    local addr=$4

    ifconfig $rep up
    ip netns add $ns
    ip link set $vf netns $ns
    ip netns exec $ns ifconfig $vf $addr/24 up
    echo "Create namespace $ns: $rep ($vf) -> $addr/24"
}

function setup() {
    title "setup"
    config_sriov 2 $NIC
    enable_switchdev
    ip l set $NIC vf 0 mac $VF1_MAC
    ip l set $NIC vf 1 mac $VF2_MAC
    unbind_vfs
    bind_vfs
    require_interfaces VF VF2 REP REP2
    create_namespace ns0 $REP $VF $VF1_IP
    create_namespace ns1 $REP2 $VF2 $VF2_IP
    ovs-vsctl add-br $OVSBR
    ovs-vsctl add-port $OVSBR $REP
    ovs-vsctl add-port $OVSBR $REP2
    ovs-vsctl add-port $OVSBR $NIC
    ip l set $NIC up
}

function check_offloaded_rules() {
    local count=$1
    title "- check for $count offloaded rules"
    RES="ovs_dump_tc_flows -m | grep 0x0800 | grep -v drop | grep offloaded:yes"
    eval $RES
    RES=`eval $RES | wc -l`
    if (( RES == $count )); then success
    else
        err $(ovs_dump_tc_flows -m | grep 0x0800 | grep -v drop | grep -v offloaded:yes)
    fi
}

function test_traffic() {
    title "Run traffic without header rewrite"
    ip netns exec ns0 ping -qI $VF $VF2_IP -c 20 -i 0.2  && success || err

    sleep 10
    title "Check, that arp entry exist"
    ip netns exec ns0 arp | grep $VF2_IP && success || err
    restart_openvswitch

    title "Add rewrite rule"
    ovs-ofctl add-flow $OVSBR \
        "in_port=$REP, dl_src=$VF1_MAC, dl_dst=$VF2_MAC, actions=mod_dl_src:$FAKE_MAC,normal"
    timeout 5 ip netns exec ns1 tcpdump -ei $VF2 -c 5 ether src $FAKE_MAC >/dev/null &
    local tdpid=$!

    sleep 1
    title "Run traffic"
    ip netns exec ns0 ping -qI $VF $VF2_IP -c 20 -i 0.2 && success || err
    check_offloaded_rules 2

    title "Verify with tcpdump"
    wait $tdpid && success || err
}

cleanup
setup
test_traffic
cleanup

test_done
