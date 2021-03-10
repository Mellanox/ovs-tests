#!/bin/bash
#
# Test OVS CT flush of tuples
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

function config_vf() {
    local ns=$1
    local vf=$2
    local rep=$3
    local ip=$4

    echo "[$ns] $vf ($ip) -> $rep"
    ifconfig $rep 0 up
    ip netns add $ns
    ip link set $vf netns $ns
    ip netns exec $ns ifconfig $vf $ip/24 up
}

function config_ovs() {
    local proto=$1
    zone=30

    echo "setup ovs"
    start_clean_openvswitch
    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs $REP2

    ovs-ofctl add-flow br-ovs "arp, actions=normal"
    ovs-ofctl add-flow br-ovs "table=0, ip,ct_state=-trk actions=ct(table=1, zone=$zone)"
    ovs-ofctl add-flow br-ovs "table=1, ip,ct_state=+trk+new actions=ct(commit, zone=$zone),normal"
    ovs-ofctl add-flow br-ovs "table=1, ip,ct_state=+trk+est actions=normal"

    ovs-ofctl dump-flows br-ovs --color
}

function run() {
    title "Test OVS CT UDP"
    config_vf ns0 $VF $REP $IP1
    config_vf ns1 $VF2 $REP2 $IP2

    proto="udp"
    config_ovs $proto

    t=15
    echo "sniff packets on $REP"
    timeout 8 tcpdump -qnnei $REP -c 20 $proto &
    pid1=$!

    title "run traffic for $t seconds"
    ip netns exec ns1 $pktgen -l -i $VF2 --src-ip $IP1 --time $((t+1)) &
    pk1=$!
    sleep 1
    ip netns exec ns0 $pktgen -i $VF1 --src-ip $IP1 --dst-ip $IP2 --time $t &
    pk2=$!

    echo "wait for sniffer"
    wait $pid1
    ovs_dump_tc_flows --names

    title "check for offloaded - no traffic on rep"
    timeout $((t-4)) tcpdump -qnnei $REP -c 1 $proto &
    pid1=$!
    verify_no_traffic $pid1

    title "check offloaded in zone $zone"
    # we cat twice. statiscally we fail first time but always succeed second time.
    cat /proc/net/nf_conntrack >/dev/null
    cat /proc/net/nf_conntrack | grep -i offload | grep $IP1 | grep $IP2 | grep "zone=$zone" || err "tuple not offloaded"

    sleep $t
    kill $pk1 &>/dev/null
    wait $pk1 $pk2 2>/dev/null

    title "del tc rules which should cause a flush"
    ovs-vsctl del-br br-ovs

    sleep 1
    title "check offloaded rules are flushed"
    cat /proc/net/nf_conntrack | grep -i offload | grep $IP1 | grep $IP2 | grep "zone=$zone" && err "tuple not flushed"
}

run
test_done
