#!/bin/bash
#
# Test OVS CT with TCP traffic and verifies flow_source optimization
#
# Bug SW #3032608: Flow source is not set for CT rules
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module act_ct
echo 1 > /proc/sys/net/netfilter/nf_conntrack_tcp_be_liberal

IP1="7.7.7.1"
IP2="7.7.7.2"


config_sriov 2 $NIC
enable_legacy $NIC
enable_switchdev $NIC
require_interfaces REP REP2

unbind_vfs
bind_vfs
reset_tc $REP
reset_tc $REP2

function cleanup() {
    rm /tmp/fsdump &>/dev/null
    rm /tmp/fsdump_parsed &>/dev/null

    conntrack -F &>/dev/null
    ip netns del ns0 2> /dev/null
    ip netns del ns1 2> /dev/null
    reset_tc $REP
    reset_tc $REP2
}
trap cleanup EXIT

function verify_ste_tuples() {
    local dev=$1

    cat /sys/kernel/debug/mlx5/$PCI/steering/fdb/* > /tmp/fsdump
    python3 mlx_steering_dump.zip -f /tmp/fsdump -vvtc > /tmp/fsdump_parsed

    tuples_stes=`cat /tmp/fsdump_parsed  | grep -i "$IP1" | grep -i "$IP2" | grep -i "TCP"`
    tuples_stes_tx=`echo "$tuples_stes" | grep -i "TX"`
    tuples_stes_rx=`echo "$tuples_stes" | grep -i "RX"`
    cnt_rx=`echo "$tuples_stes_rx" | grep -c '.'`
    cnt_tx=`echo "$tuples_stes_tx" | grep -c '.'`
    echo "$tuples_stes_rx"
    echo "$tuples_stes_tx"
    echo "rx count: $cnt_rx, tx count: $cnt_tx"

    [[ $cnt_rx -gt 0 ]] && err "Wrong RX ste count (expected 0)"
    [[ $cnt_tx -le 0 ]] && err "Wrong TX ste count (expected > 0)"
}

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
    conns=3

    echo "run traffic for $t seconds"
    ip netns exec ns1 timeout $((t+1)) iperf -s &
    sleep 0.5
    ip netns exec ns0 timeout $((t+1)) iperf -t $t -c $IP2 -P $conns &

    sleep 2
    pidof iperf &>/dev/null || err "iperf failed"

    echo "sniff packets on $VF2"
    ip netns exec ns1 timeout $t tcpdump -qnnei $VF2 -c 10 tcp &
    pid1=$!

    echo "sniff packets on $REP"
    timeout $((t-4)) tcpdump -qnnei $REP -c 10 'tcp' &
    pid=$!

    ovs_dump_tc_flows --names
    ovs_dump_tc_flows --names | grep -q "ct(.*commit.*)" || err "Expected ct commit action"

    verify_ste_tuples $NIC

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
