#!/bin/bash
#
# Test OVS CT TCP traffic
#

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

    t=12

    echo "run traffic for $t seconds"
    ip netns exec ns1 timeout $((t+1)) iperf -s &
    sleep 0.5
    ip netns exec ns0 timeout $((t+1)) iperf -t $t -c $IP2 -P 3 &

    sleep 2
    pidof iperf &>/dev/null || err "iperf failed"

    echo "sniff packets on $VF2"
    ip netns exec ns1 timeout 4 tcpdump -qnnei $VF2 -c 10 tcp &
    pid1=$!

    echo "sniff packets on $REP"
    timeout 4 tcpdump -qnnei $REP -c 10 'tcp' &
    pid=$!

    ovs_dump_tc_flows --names
    ovs_dump_tc_flows --names | grep -q "ct(.*commit.*)" || err "Expected ct commit action"

    sleep $t
    killall -9 iperf &>/dev/null
    wait $! 2>/dev/null

    title "Verify traffic on $VF2"
    verify_have_traffic $pid1

    title "Verify no traffic on $REP"
    verify_no_traffic $pid

    ovs-vsctl del-br br-ovs
}

cleanup
run
test_done
