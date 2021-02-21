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

enable_switchdev
require_interfaces REP REP2
unbind_vfs
bind_vfs
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

    ovs-ofctl add-flow br-ovs in_port=$REP,dl_type=0x0806,actions=output:$REP2
    ovs-ofctl add-flow br-ovs in_port=$REP2,dl_type=0x0806,actions=output:$REP

    ovs-ofctl add-flow br-ovs "table=0, $proto,ct_state=-trk actions=ct(table=1)"
    ovs-ofctl add-flow br-ovs "table=1, $proto,ct_state=+trk+new actions=ct(commit),normal"
    ovs-ofctl add-flow br-ovs "table=1, $proto,ct_state=+trk+est actions=normal"

    ovs-ofctl dump-flows br-ovs --color
}

function verify_count() {
    echo
    echo "verify number of offload flows in connrack ~$port_count"
    count=`cat /proc/net/nf_conntrack | grep -i offload | wc -l`
    echo "flows: $count"
    # allow to miss some its not perfect tool
    let count2=count+200
    if [ "$count2" -lt $port_count ]; then
        err "Expected ~$port_count flows"
    else
        success
    fi
}

function run() {
    title "Test OVS CT UDP"
    config_vf ns0 $VF $REP $IP1
    config_vf ns1 $VF2 $REP2 $IP2

    proto="udp"
    config_ovs $proto

    t=20
    port_count=4000
    echo "sniff packets on $REP"
    timeout $t tcpdump -qnnei $REP -c 2 $proto &
    pid1=$!

    echo "run traffic for $t seconds"
    ip netns exec ns1 $pktgen -l -i $VF2 --src-ip $IP1 --time $((t+1)) &
    pk1=$!
    sleep 1
    port1=`echo $RANDOM % 1000 + 1000 | bc`
    ip netns exec ns0 $pktgen -i $VF1 --src-ip $IP1 --dst-ip $IP2 --time $t --src-port $port1 --src-port-count $port_count --dst-port $port_count --dst-port-count 1 --pkt-count 1 --inter 0 &
    pk2=$!

    # first 4 packets not offloaded until conn is in established state.
    sleep 2
    verify_have_traffic $pid1

    echo "sniff packets on $REP"
    timeout $((t-4)) tcpdump -qnnei $REP -c 10 $proto &
    pid2=$!

    sleep $t
    kill $pk1 &>/dev/null
    wait $pk1 $pk2 2>/dev/null

    verify_no_traffic $pid2
    verify_count

    sleep 1
    ovs-vsctl del-br br-ovs
}


run
test_done
