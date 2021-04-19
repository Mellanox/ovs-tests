#!/bin/bash
#
# Test OVS CT TCP traffic
#
# Bug SW #2582618: [BF-2, CX5, CX6dx] ovs crash after purge while send stress http traffic Trex

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module act_ct
echo 1 > /proc/sys/net/netfilter/nf_conntrack_tcp_be_liberal

IP1="7.7.7.1"
IP2="7.7.7.2"

config_sriov 2
enable_switchdev
require_interfaces REP REP2
unbind_vfs
bind_vfs
reset_tc $REP
reset_tc $REP2

function cleanup() {
    conntrack -F &>/dev/null
    ip netns del ns0 2> /dev/null
    ip netns del ns1 2> /dev/null
    reset_tc $REP
    reset_tc $REP2
}
trap cleanup EXIT

function run() {
    title "Test OVS CT TCP"
    config_vf ns0 $VF $REP $IP1
    config_vf ns1 $VF2 $REP2 $IP2

    echo "setup ovs"
    start_clean_openvswitch
    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs $REP2

    zone=99

    ovs-ofctl del-flows br-ovs
    ovs-ofctl add-flow br-ovs arp,actions=normal
    ovs-ofctl add-flow br-ovs "table=0, ip,ct_state=-trk actions=ct(table=1,zone=$zone)"
    ovs-ofctl add-flow br-ovs "table=1, ip,ct_state=+trk+new actions=ct(zone=$zone, commit),normal"
    ovs-ofctl add-flow br-ovs "table=1, ip,ct_zone=$zone,ct_state=+trk+est actions=normal"

    ovs-ofctl dump-flows br-ovs --color

    t=15

    echo "run traffic for $t seconds"
    ip netns exec ns1 timeout $((t+1)) iperf -s &
    p1=$!
    sleep 0.5
    ip netns exec ns0 timeout $((t+1)) iperf -t $t -c $IP2 -P 12 &
    p2=$!

    sleep 2
    pidof iperf &>/dev/null || err "iperf failed"

    title "revalidator/purge"
    ovs-appctl revalidator/purge
    sleep 1
    if ! pidof ovs-vswitchd &>/dev/null ; then
        err "ovs-vswitchd crashed"
    fi

    killall -q -9 iperf &>/dev/null
    wait $p1 $p2 &>/dev/null

    start_clean_openvswitch
}

cleanup
run
test_done
