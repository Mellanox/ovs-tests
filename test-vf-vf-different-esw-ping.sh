#!/bin/bash
#
#  Testing ping between VFs on different eSwitch.
#

NIC=${1:-ens5f0}
VF=${2:-ens5f2}
REP=${4:-ens5f0_0}
my_dir="$(dirname "$0")"
. $my_dir/common.sh

test -z "$NIC2" && fail "Missing NIC2"

IP1="7.7.7.1"
IP2="7.7.7.2"

MULTIPATH=${MULTIPATH:-0}

function cleanup() {
    ip netns del ns0 2> /dev/null
    ip netns del ns1 2> /dev/null
}

function config_vf() {
    local ns=$1
    local vf=$2
    local rep=$3
    local ip=$4

    echo "$ns : $vf ($ip) -> $rep"
    ifconfig $rep 0 up
    ip netns add $ns
    ip link set $vf netns $ns
    ip netns exec $ns ifconfig $vf $ip/24 up
}

function disable_sriov() {
    title "- Disable SRIOV"
    echo 0 > /sys/class/net/$NIC/device/sriov_numvfs
    echo 0 > /sys/class/net/$NIC2/device/sriov_numvfs
}

function enable_sriov() {
    title "- Enable SRIOV"
    echo 2 > /sys/class/net/$NIC/device/sriov_numvfs
    echo 2 > /sys/class/net/$NIC2/device/sriov_numvfs
}

function is_offloaded_rules() {
    local rep=$1
    local src_mac=$2
    local dst_mac=$3
    local rules=`tc -s filter show dev $rep ingress | awk '$0 != "" {printf "%s, ",$0} $0 == "" {printf "\n"}' | tr -d ","`
    local rule_offloaded=`echo "$rules" | grep "src_mac $src_mac" | grep "dst_mac $dst_mac" | grep "eth_type ipv4" | grep -w in_hw`
    if [ -z "$rule_offloaded" ]; then 
	return 1
    fi
    return 0
}

disable_sriov
if [ $MULTIPATH == 1 ]; then
    enable_multipath || fail
fi
enable_sriov
enable_switchdev $NIC
enable_switchdev $NIC2
bind_vfs $NIC
bind_vfs $NIC2

VF2=`get_vf 0 $NIC2`
REP2=`get_rep 0 $NIC2`
if [ -z "$REP2" ]; then
    fail "Missing rep $rep"
    exit 1
fi

cleanup
start_clean_openvswitch
config_vf ns0 $VF $REP $IP1
config_vf ns1 $VF2 $REP2 $IP2
BR=ov1
ovs-vsctl add-br $BR
ovs-vsctl add-port $BR $REP
ovs-vsctl add-port $BR $REP2

title "Test ping $VF($IP1) -> $VF2($IP2)"
ip netns exec ns0 ping -q -c 10 -i 0.2 -w 2 $IP2 && success || err

dst_mac=`ip netns exec ns1 ip link show $VF2 | grep ether | awk '{print $2}'`
src_mac=`ip netns exec ns0 ip link show $VF1 | grep ether | awk '{print $2}'`

title "Check $VF1->$VF2 rule offloaded"
is_offloaded_rules $REP $src_mac $dst_mac && success || err "Rules are not offloaded"

title "Check $VF2->$VF1 rule offloaded"
is_offloaded_rules $REP2 $dst_mac $src_mac && success || err "Rules are not offloaded"

del_all_bridges
cleanup
if [ $MULTIPATH == 1 ]; then
    disable_sriov
    disable_multipath
fi
test_done
