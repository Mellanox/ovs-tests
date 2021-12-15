#!/bin/bash
#
# Test OVS CT unidiectional traffic
# Feature #2829954: CX5 ASAP2 Kernel: Need offload UDP uni-directional traffic under CT
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
    title "Test OVS CT unidirectional traffic"
    config_vf ns0 $VF $REP $IP1
    config_vf ns1 $VF2 $REP2 $IP2

    title "Case #1: TCP cons in 'new' state will not be offloaded"
    proto="tcp"
    config_ovs $proto

    port_count=4
    port1=`echo $RANDOM % 1000 + 1000 | bc`
    echo "run unidirectional tcp traffic for $t seconds"
    ip netns exec ns0 $pktgen -i $VF1 --syn-flood --src-ip $IP1 --dst-ip $IP2 --time 2 --src-port $port1 --src-port-count $port_count --dst-port $port_count --dst-port-count 1 --pkt-count 1 --inter 0 &
    timeout 2 tcpdump -qnnei $REP -c 4 &
    pid1=$!
    sleep 2
    verify_have_traffic $pid1

    ip netns exec ns0 $pktgen -i $VF1 --syn-flood --src-ip $IP1 --dst-ip $IP2 --time 2 --src-port $port1 --src-port-count $port_count --dst-port $port_count --dst-port-count 1 --pkt-count 1 --inter 0 &
    timeout 2 tcpdump -qnnei $REP -c 4 &
    pid1=$!
    sleep 2
    verify_have_traffic $pid1

    sleep 1
    title "Case #2: UDP cons in 'new' state will be offloaded"
    t=10
    proto="udp"
    config_ovs $proto
    port_count=4
    port1=`echo $RANDOM % 1000 + 1000 | bc`
    echo "run unidirectional udp traffic for 3 seconds"
    ip netns exec ns0 $pktgen -i $VF1 --src-ip $IP1 --dst-ip $IP2 --time $((t+3)) --src-port $port1 --src-port-count $port_count --dst-port $port_count --dst-port-count 1 --pkt-count 1 --inter 0 &
    echo "sniff packets on $REP"
    timeout 3 tcpdump -qnnei $REP -c 2 $proto &
    pid1=$!
    sleep 3
    verify_have_traffic $pid1
    echo "run unidirectional udp traffic again for $((t+3)) seconds"
    ip netns exec ns0 $pktgen -i $VF1 --src-ip $IP1 --dst-ip $IP2 --time $((t+3)) --src-port $port1 --src-port-count $port_count --dst-port $port_count --dst-port-count 1 --pkt-count 1 --inter 0 &
    echo "sniff packets on $REP"
    timeout 3 tcpdump -qnnei $REP -c 2 $proto &
    pid1=$!
    sleep 3
    verify_no_traffic $pid1

    sleep 1
    title "Case #3: UDP cons changed to 'est' state will remove 'new' from hw and be offloaded again"
    timeout 3 tcpdump -qnnei $REP -c 2 $proto &
    pid1=$!
    echo "Start response traffic for $t seconds to make flows esteblished"
    ip netns exec ns1 $pktgen -l -i $VF2 --src-ip $IP1 --time $t &
    sleep 3
    verify_have_traffic $pid1

    timeout $((t-3)) tcpdump -qnnei $REP -c 2 $proto &
    pid1=$!
    sleep $((t-3))
    verify_no_traffic $pid1

    echo "sniff packets on $REP"
    timeout $t tcpdump -qnnei $REP -c 10 $proto &
    pid1=$!
    verify_no_traffic $pid1

    sleep 1
    title "Case #4: UDP cons in 'new' state scale test"
    port_count=4000
    echo "run warmup traffic for $t seconds"
    sleep 1
    port1=`echo $RANDOM % 1000 + 1000 | bc`
    ip netns exec ns0 $pktgen -i $VF1 --src-ip $IP1 --dst-ip $IP2 --time $t --src-port $port1 --src-port-count $port_count --dst-port $port_count --dst-port-count 1 --pkt-count 1 --inter 0 &
    pk2=$!

    timeout $((t-5)) tcpdump -qnnei $REP -c 10 $proto &
    pid1=$!
    sleep $((t-5))
    verify_have_traffic $pid1

    sleep 5

    echo "run unidirectional traffic for $t seconds"
    ip netns exec ns0 $pktgen -i $VF1 --src-ip $IP1 --dst-ip $IP2 --time $t --src-port $port1 --src-port-count $port_count --dst-port $port_count --dst-port-count 1 --pkt-count 1 --inter 0 &
    echo "sniff packets on $REP"
    timeout $t tcpdump -qnnei $REP -c 10 $proto &
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
