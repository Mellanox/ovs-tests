#!/bin/bash
#
# Test OVS CT udp traffic with VF mirror
#
# Bug SW #1604925: traffic is not offloaded with OVS and VF mirror
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-ovs-ct.sh
pktgen=$my_dir/scapy-traffic-tester.py

min_nic_cx6dx
require_module act_ct

IP1="7.7.7.1"
IP2="7.7.7.2"

config_sriov 3
enable_switchdev
REP3=`get_rep 2`
require_interfaces REP REP2 REP3
unbind_vfs
bind_vfs
VF3=`get_vf 2`
reset_tc $REP
reset_tc $REP2

function cleanup() {
    ip netns del ns0 2> /dev/null
    ip netns del ns1 2> /dev/null
    reset_tc $REP
    reset_tc $REP2
}
trap cleanup EXIT

function config_ovs() {
    local proto=$1

    echo "setup ovs"
    start_clean_openvswitch
    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs $REP2
    ovs-vsctl add-port br-ovs $REP3
    ovs-vsctl -- --id=@p1 get port $REP3 -- \
                --id=@m create mirror name=m1 select-all=true output-port=@p1 -- \
                set bridge br-ovs mirrors=@m || err "Failed to set mirror port"
    #ovs-vsctl list Bridge br-ovs | grep mirrors
    #ovs-vsctl clear bridge br-ovs mirrors

    ovs-ofctl add-flow br-ovs in_port=$REP,dl_type=0x0806,actions=output:$REP2
    ovs-ofctl add-flow br-ovs in_port=$REP2,dl_type=0x0806,actions=output:$REP

    ovs-ofctl add-flow br-ovs "table=0, $proto,ct_state=-trk actions=ct(table=1)"
    ovs-ofctl add-flow br-ovs "table=1, $proto,ct_state=+trk+new actions=ct(commit),normal"
    ovs-ofctl add-flow br-ovs "table=1, $proto,ct_state=+trk+est actions=normal"

    ovs-ofctl dump-flows br-ovs --color
}

function run() {
    title "Test OVS CT UDP with VF mirror"
    config_vf ns0 $VF $REP $IP1
    config_vf ns1 $VF2 $REP2 $IP2
    ip link set dev $REP3 up
    ip link set dev $VF3 up

    proto="udp"
    config_ovs $proto

    t=10
    echo "sniff packets on $REP"
    timeout $t tcpdump -qnnei $REP -c 2 $proto &
    pid1=$!

    echo "run traffic for $t seconds"
    ip netns exec ns1 $pktgen -l -i $VF2 --src-ip $IP1 --time $((t+1)) &
    pk1=$!
    sleep 1
    ip netns exec ns0 $pktgen -i $VF1 --src-ip $IP1 --dst-ip $IP2 --time $t &
    pk2=$!

    verify_ct_udp_have_traffic $pid1

    timeout $t tcpdump -qnnei $REP -c 1 $proto &
    pid2=$!

    echo "sniff packets on $VF3"
    timeout 2 tcpdump -qnnei $VF3 -c 20 $proto &
    pid3=$!

    sleep $t
    kill $pk1 &>/dev/null
    wait $pk1 $pk2 2>/dev/null

    tc -s filter show dev $REP ingress

    title "Verify offload on $REP"
    verify_no_traffic $pid2
    title "Verify mirror traffic on $VF3"
    verify_have_traffic $pid3

    ovs-vsctl del-br br-ovs

    # wait for traces as merging & offloading is done in workqueue.
    sleep 3
}


run
test_done
