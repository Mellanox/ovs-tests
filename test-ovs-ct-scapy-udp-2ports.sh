#!/bin/bash
#
# Test OVS CT udp traffic
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh
pktgen=$my_dir/scapy-traffic-tester.py

require_module act_ct

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

function config_ovs() {
    local proto=$1

    echo "setup ovs"
    start_clean_openvswitch
    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs $REP2
    ovs-vsctl add-port br-ovs $REP3
    ovs-vsctl add-port br-ovs $REP4

    ovs-ofctl add-flow br-ovs in_port=$REP,dl_type=0x0806,actions=output:$REP2
    ovs-ofctl add-flow br-ovs in_port=$REP2,dl_type=0x0806,actions=output:$REP

    ovs-ofctl add-flow br-ovs "table=0, $proto,ct_state=-trk actions=ct(table=1)"
    ovs-ofctl add-flow br-ovs "table=1, $proto,ct_state=+trk+new actions=ct(commit),normal"
    ovs-ofctl add-flow br-ovs "table=1, $proto,ct_state=+trk+est actions=normal"

    ovs-ofctl dump-flows br-ovs --color
}

function run() {
    title "Test OVS CT UDP"
    ip netns add ns0
    ip netns add ns1
    config_vf ns0 $VF $REP $IP1
    config_vf ns1 $VF2 $REP2 $IP2
    config_vf ns0 $VF3 $REP3 $IP3
    config_vf ns1 $VF4 $REP4 $IP4

    proto="udp"
    config_ovs $proto

    t=10
    echo "sniff packets on $REP"
    timeout $t tcpdump -qnnei $REP -c 2 $proto &
    pid1=$!
    echo "sniff packets on $REP3"
    timeout $t tcpdump -qnnei $REP3 -c 2 $proto &
    pid2=$!

    echo "run traffic for $t seconds"
    ip netns exec ns1 $pktgen -l -i $VF2 --src-ip $IP1 --time $((t+1)) &
    pk1=$!
    ip netns exec ns1 $pktgen -l -i $VF4 --src-ip $IP3 --time $((t+1)) &
    pk2=$!
    sleep 1
    ip netns exec ns0 $pktgen -i $VF1 --src-ip $IP1 --dst-ip $IP2 --time $t &
    pk3=$!
    ip netns exec ns0 $pktgen -i $VF3 --src-ip $IP3 --dst-ip $IP4 --time $t &
    pk4=$!

    # first 4 packets not offloaded until conn is in established state.
    sleep 2
    title "test for traffic on $REP"
    verify_have_traffic $pid1
    title "test for traffic on $REP3"
    verify_have_traffic $pid2

    echo "sniff packets on $REP"
    timeout $t tcpdump -qnnei $REP -c 5 $proto &
    pid3=$!
    echo "sniff packets on $REP3"
    timeout $t tcpdump -qnnei $REP3 -c 5 $proto &
    pid4=$!

    sleep $t
    kill $pk1 &>/dev/null
    kill $pk2 &>/dev/null
    wait $pk3 $pk4 2>/dev/null

    title "test for no traffic on $REP"
    verify_no_traffic $pid3
    title "test for no traffic on $REP3"
    verify_no_traffic $pid4

    ovs-vsctl del-br br-ovs

    # wait for traces as merging & offloading is done in workqueue.
    sleep 3
}


run
test_done
