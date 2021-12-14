#!/bin/bash
#
# Try to reproduce bug after ovs restart without touching ports or dumping rules. rules are not added to TC dp.
#
# Bug SW #2895340: [for-upstream ovs] ovs doesn’t use tc to offload if ovs is configured then restarted

my_dir="$(dirname "$0")"
. $my_dir/common.sh

VM1_IP="7.7.7.1"
VM2_IP="7.7.7.2"


function cleanup() {
    echo "cleanup"
    start_clean_openvswitch
    ip netns del ns0 &> /dev/null
    ifconfig $VF2 0
}

config_sriov 2
enable_switchdev
unbind_vfs
bind_vfs
require_interfaces VF VF2 REP REP2
cleanup

echo "setup ns"
ifconfig $VF2 $VM1_IP/24 up
ip netns add ns0
ip link set $VF netns ns0
ip netns exec ns0 ifconfig $VF $VM2_IP/24 up
ifconfig $REP up
ifconfig $REP2 up

echo "setup ovs"
ovs-vsctl add-br brv-1
ovs-vsctl add-port brv-1 $REP
ovs-vsctl add-port brv-1 $REP2

title "restart ovs"
restart_openvswitch

function check_offloaded_rules() {
    local count=$1
    local cmd="ovs_dump_tc_flows | grep 0x0800 | grep -v drop"
    eval $cmd
    RES=`eval $cmd | wc -l`
    if (( RES == $count )); then success; else err; fi

    if eval $cmd | grep "packets:0, bytes:0" ; then
        err "packets:0, bytes:0"
    fi
}


ping -q -w 2 -i 0.1 $VM2_IP && success || err

title "Verify we have 2 rules"
check_offloaded_rules 2

ovs_dump_flows --names -m | grep 0x0800

cleanup
test_done
