#!/bin/bash
#
#  Testing ping between VFs on different eSwitch.
#  Bug SW #1512703: vf to vf ping on different eswitch is broken
#
#  Test will fail if NUM_OFS_VFS > 64
#  For ConnectX4Lx NUM_OF_VFS should be 32.
#  For ConnectX5, FW guys are working on fix to support 64 (should be part of
#  Nov GA). (16.24.0286)
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

test -z "$NIC2" && fail "Missing NIC2"

IP1="7.7.7.1"
IP2="7.7.7.2"

function cleanup() {
    ip netns del ns0 2> /dev/null
    ip netns del ns1 2> /dev/null
    config_sriov 0 $NIC2
}

function is_offloaded_rules() {
    local rep=$1
    local src_mac=$2
    local dst_mac=$3
    tc -s filter show dev $rep ingress
    local rules=`tc -s filter show dev $rep ingress | awk '$0 != "" {printf "%s, ",$0} $0 == "" {printf "\n"}' | tr -d ","`
    local rule_offloaded=`echo "$rules" | grep "src_mac $src_mac" | grep "dst_mac $dst_mac" | grep "eth_type ipv4" | grep -w in_hw`
    if [ -z "$rule_offloaded" ]; then
        err "Rules are not offloaded"
        return
    fi
    local used=`tc -s filter show protocol ip dev $rep ingress |grep -o "used [0-9]*" | awk {'print $2'}`
    if [ -z "$used" ]; then
        err "Cannot read used value"
        return
    fi
    if [ "$used" -gt 3 ]; then
        err "Used value not being reset"
        return
    fi
    success
}


cleanup
disable_sriov
enable_sriov
enable_switchdev $NIC
enable_switchdev $NIC2
bind_vfs $NIC
bind_vfs $NIC2

VF2=`get_vf 0 $NIC2`
REP2=`get_rep 0 $NIC2`
if [ -z "$REP2" ]; then
    fail "Missing rep on second port"
fi

require_interfaces VF VF2 REP REP2
start_clean_openvswitch
config_vf ns0 $VF $REP $IP1
config_vf ns1 $VF2 $REP2 $IP2
BR=ov1
ovs-vsctl add-br $BR
ovs-vsctl add-port $BR $REP
ovs-vsctl add-port $BR $REP2

title "Test ping $VF($IP1) -> $VF2($IP2)"
ip netns exec ns0 ping -q -c 1 -w 2 $IP2
timeout 2 tcpdump -nnei $REP -c 3 'icmp' &
tdpid=$!
ip netns exec ns0 ping -q -i 0.5 -w 5 $IP2 && success || err

dst_mac=`ip netns exec ns1 ip link show $VF2 | grep ether | awk '{print $2}'`
src_mac=`ip netns exec ns0 ip link show $VF1 | grep ether | awk '{print $2}'`

# Do sleep to make sure that stats were updated before rule dump
sleep 1

title "Check $VF1->$VF2 rule offloaded"
is_offloaded_rules $REP $src_mac $dst_mac

title "Check $VF2->$VF1 rule offloaded"
is_offloaded_rules $REP2 $dst_mac $src_mac

title "Verify with tcpdump"
wait $tdpid && err || success

ovs_clear_bridges
cleanup
test_done
