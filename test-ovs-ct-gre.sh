#!/bin/bash
#
# Test OVS CT with GRE traffic
#
# Scrum Task #3011515: [MT CT] Add back support for GRE tuples
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module act_ct
echo 1 > /proc/sys/net/netfilter/nf_conntrack_tcp_be_liberal

IP1="7.7.7.1"
IP2="7.7.7.2"
INNER1="5.5.5.5"
INNER2="5.5.5.6"

config_sriov 2
enable_switchdev
require_interfaces REP REP2
unbind_vfs
bind_vfs
reset_tc $REP
reset_tc $REP2

function cleanup() {
    killall -9 iperf &>/dev/null
    conntrack -F &>/dev/null
    ip netns del ns0 2> /dev/null
    ip netns del ns1 2> /dev/null
    reset_tc $REP
    reset_tc $REP2
    rm /tmp/repdump 2>/dev/null
}

trap cleanup EXIT

function config_gre_setup() {
    config_vf ns0 $VF $REP $IP1
    config_vf ns1 $VF2 $REP2 $IP2

    ip netns exec ns0 ip link add name gre_sys type gretap dev $VF remote $IP2 nocsum
    ip netns exec ns1 ip link add name gre_sys type gretap dev $VF2 remote $IP1 nocsum
    ip netns exec ns0 ifconfig gre_sys $INNER1/24 up
    ip netns exec ns1 ifconfig gre_sys $INNER2/24 up
}

function run() {
    title "Test OVS CT GRE"
    config_gre_setup

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
    sleep 0.5
    ip netns exec ns0 timeout $((t+1)) iperf -t $t -c $INNER2 &

    sleep 2
    pidof iperf &>/dev/null || err "iperf failed"

    sleep 2

    echo "Started sniffing packets on $VF2"
    ip netns exec ns1 timeout $((t-4)) tcpdump -qnnei $VF2 -c 1 proto gre 1>/dev/null 2>&1 &
    pid1=$!

    echo "Started sniffing packets on $REP"
    timeout $((t-4)) tcpdump -qnnei $REP -c 1 proto gre 1>/tmp/repdump 2>&1 &
    pid2=$!


    title "Verify offloaded gre tuple"
    res=`cat /proc/net/nf_conntrack | grep zone=$zone`
    echo "$res"
    echo "$res" | grep -q -i "offload" || err "Expected offloaded gre tuple"

    title "Verify dump flows commit action"
    res=`ovs_dump_tc_flows --names | grep 0x0800`
    echo "$res"
    echo "$res" | grep -q -i "ct(.*commit.*)" || err "Expected ct commit action"

    sleep $t
    killall -9 iperf &>/dev/null
    wait $! 2>/dev/null

    title "Verify traffic on $VF2"
    verify_have_traffic $pid1

    title "Verify no traffic on $REP"
    verify_no_traffic $pid2
    if [ $TEST_FAILED != 0 ]; then
        cat /tmp/repdump
    fi

    ovs-vsctl del-br br-ovs
}

cleanup
run
test_done
