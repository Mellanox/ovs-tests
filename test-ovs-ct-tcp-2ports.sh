#!/bin/bash
#
# Test OVS CT TCP traffic
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_interface NIC2

require_module act_ct
echo 1 > /proc/sys/net/netfilter/nf_conntrack_tcp_be_liberal

IP1="7.7.7.1"
IP2="7.7.7.2"
IP3="8.8.8.1"
IP4="8.8.8.2"

function cleanup() {
    ip netns del ns0 2> /dev/null
    ip netns del ns1 2> /dev/null
    reset_tc $REP
    reset_tc $REP2
    config_sriov 0 $NIC2
}
trap cleanup EXIT

config_sriov 2 $NIC
config_sriov 2 $NIC2
enable_switchdev
enable_switchdev $NIC2
unbind_vfs
unbind_vfs $NIC2
bind_vfs
bind_vfs $NIC2
VF3=`get_vf 0 $NIC2`
VF4=`get_vf 1 $NIC2`
REP3=`get_rep 0 $NIC2`
REP4=`get_rep 1 $NIC2`
if [ -z "$REP3" ]; then
    fail "Missing rep from $NIC2"
fi
require_interfaces REP REP2 REP3 REP4
reset_tc $REP
reset_tc $REP2

function config_vf() {
    local ns=$1
    local vf=$2
    local rep=$3
    local ip=$4

    echo "[$ns] $vf ($ip) -> $rep"
    ifconfig $rep 0 up
    ip link set $vf netns $ns
    ip netns exec $ns ifconfig $vf $ip/24 up
}

function run() {
    title "Test OVS CT TCP"
    ip netns add ns0
    ip netns add ns1
    config_vf ns0 $VF $REP $IP1
    config_vf ns1 $VF2 $REP2 $IP2
    config_vf ns0 $VF3 $REP3 $IP3
    config_vf ns1 $VF4 $REP4 $IP4

    echo "setup ovs"
    start_clean_openvswitch
    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs $REP2
    ovs-vsctl add-port br-ovs $REP3
    ovs-vsctl add-port br-ovs $REP4

    ovs-ofctl add-flow br-ovs arp,actions=normal
    ovs-ofctl add-flow br-ovs "table=0, ip,ct_state=-trk actions=ct(table=1)"
    ovs-ofctl add-flow br-ovs "table=1, ip,ct_state=+trk+new actions=ct(commit),normal"
    ovs-ofctl add-flow br-ovs "table=1, ip,ct_state=+trk+est actions=normal"

    ovs-ofctl dump-flows br-ovs --color

    echo "run traffic"
    t=12
    echo "run traffic for $t seconds"
    ip netns exec ns1 timeout $((t+1)) iperf -s &
    sleep 0.5
    ip netns exec ns0 timeout $((t+1)) iperf -t $t -c $IP2 -P3 &
    ip netns exec ns0 timeout $((t+1)) iperf -t $t -c $IP4 -P3 &

    sleep 4
    pidof iperf &>/dev/null || err "iperf failed"

    echo "sniff packets on $REP"
    timeout $t tcpdump -qnnei $REP -c 10 'tcp' &
    pid=$!
    echo "sniff packets on $REP3"
    timeout $t tcpdump -qnnei $REP3 -c 10 'tcp' &
    pid2=$!

    sleep $t
    killall -9 iperf &>/dev/null
    wait $! 2>/dev/null

    test_no_traffic $pid
    test_no_traffic $pid2

    ovs-vsctl del-br br-ovs
}

function test_no_traffic() {
    local pid=$1
    wait $pid
    rc=$?
    if [[ $rc -eq 124 ]]; then
        :
    elif [[ $rc -eq 0 ]]; then
        err "Didn't expect to see packets"
    else
        err "Tcpdump failed"
    fi
}


run
test_done
