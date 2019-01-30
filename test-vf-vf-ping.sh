#!/bin/bash
#
# 
#

NIC=${1:-ens5f0}
VF=${2:-ens5f2}
REP=${4:-ens5f0_0}
my_dir="$(dirname "$0")"
. $my_dir/common.sh

test -z "$VF2" && fail "Missing VF2"
test -z "$REP2" && fail "Missing REP2"

IP1="7.7.7.1"
IP2="7.7.7.2"

MULTIPATH=${MULTIPATH:-0}
[ $MULTIPATH == 1 ] && require_multipath_support

function cleanup() {
    ip netns del ns0 2> /dev/null
    ip netns del ns1 2> /dev/null
    sleep 0.5 # wait for VF to bind back
    for i in $REP $REP2 $VF $VF2 ; do
        ip link set $i mtu 1500 &>/dev/null
        ifconfig $i 0 &>/dev/null
    done
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

if [ $MULTIPATH == 1 ]; then
    disable_sriov
    enable_multipath || fail
    enable_sriov
    enable_switchdev $NIC
    enable_switchdev $NIC2
    unbind_vfs $NIC
    unbind_vfs $NIC2
    bind_vfs $NIC
    bind_vfs $NIC2
else
    enable_switchdev_if_no_rep $REP
    unbind_vfs
    bind_vfs
fi

trap cleanup EXIT
cleanup
start_clean_openvswitch
start_check_syndrome
config_vf ns0 $VF $REP $IP1
config_vf ns1 $VF2 $REP2 $IP2
BR=ov1
ovs-vsctl add-br $BR
ovs-vsctl add-port $BR $REP
ovs-vsctl add-port $BR $REP2

title "Test ping $VF($IP1) -> $VF2($IP2)"
ip netns exec ns0 ping -q -c 10 -i 0.2 -w 4 $IP2 && success || err

function set_mtu() {
    local mtu=$1
    ip link set $REP mtu $mtu || fail "Failed to set mtu to $REP"
    ip link set $REP2 mtu $mtu || fail "Failed to set mtu to $REP2"
    ip netns exec ns0 ip link set $VF mtu $mtu || fail "Failed to set mtu to $VF"
    ip netns exec ns1 ip link set $VF2 mtu $mtu || fail "Failed to set mtu to $VF2"
}

function verify_timedout() {
    local pid=$1
    wait $pid
    local rc=$?
    [ $rc == 124 ] && success || err "Process $pid rc $rc"
}

function start_sniff() {
    local dev=$1
    local filter=$2
    timeout 5 tcpdump -qnnei $dev -c 4 $filter &
    tpid=$!
    sleep 0.5
}

echo "start sniff $REP"
start_sniff $REP icmp

mtu=576
title "Test ping $VF($IP1) -> $VF2($IP2) MTU $mtu"
set_mtu $mtu
ip netns exec ns0 ping -q -f -w 4 $IP2 && success || err

echo "verify tcpdump"
verify_timedout $tpid

del_all_bridges
cleanup
if [ $MULTIPATH == 1 ]; then
    disable_sriov
    disable_multipath
    enable_sriov
fi
check_syndrome
test_done
