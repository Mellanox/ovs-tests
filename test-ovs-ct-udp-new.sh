#!/bin/bash
#
# Test OVS CT UDP NEW connection offload with iperf
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
    ip netns del ns0 2> /dev/null
    ip netns del ns1 2> /dev/null
    reset_tc $REP
    reset_tc $REP2
}
trap cleanup EXIT

function run() {
    title "Test OVS CT UDP"
    config_vf ns0 $VF $REP $IP1
    config_vf ns1 $VF2 $REP2 $IP2

    echo "setup ovs"
    start_clean_openvswitch
    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs $REP2

    ovs-ofctl add-flow br-ovs arp,actions=normal
    ovs-ofctl add-flow br-ovs "table=0, ip,ct_state=-trk actions=ct(table=1)"
    ovs-ofctl add-flow br-ovs "table=1, ip,ct_state=+trk+new actions=ct(commit),normal"
    ovs-ofctl add-flow br-ovs "table=1, ip,ct_state=+trk+est actions=normal"

    ovs-ofctl dump-flows br-ovs --color

    echo "run traffic"
    t=10
    echo "run traffic for $t seconds"
    ip netns exec ns1 timeout $((t+5)) iperf -s -D -u
    sleep 0.5
    # First connection with empty TC qdisc will not be offloaded until after at
    # least 1 second has passed due to driver callback only being registered as
    # a result of adding first CT action to hardware. Run a warmup iperf run to
    # ensure the callback is registered.
    ip netns exec ns0 timeout 1 iperf -t 1 -c $IP2 -u -b 10pps
    ip netns exec ns0 timeout $((t+1)) iperf -t $t -c $IP2 -u -b 10pps &

    sleep 0.5
    pidof iperf &>/dev/null || err "iperf failed"

    echo "sniff packets on $REP"
    timeout $((t-4)) tcpdump -nnvvvi $REP -c 5 'udp' &
    pid=$!

    sleep 1
    ovs_dump_tc_flows --names
    conntrack -L | grep udp | grep "dst=$IP2" | grep "\[UNREPLIED\]" | grep -q "\[OFFLOAD\]" || err "Offloaded unreplied UDP connection not found"

    sleep $t
    killall -9 iperf &>/dev/null
    wait $! 2>/dev/null

    verify_no_traffic $pid

    ovs-vsctl del-br br-ovs
}


run
test_done
