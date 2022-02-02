#!/bin/bash
#
# Test OVS ipv6 tcp traffic with ttl/tos/label rewrite before and after CT
#
# Bug SW #2698668: [OVN] s_pf0vf2: hw csum failure for mlx5
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

IP1="7:7:7::1"
IP2="7:7:7::2"

config_sriov 2
enable_switchdev
require_interfaces REP REP2
unbind_vfs
bind_vfs
reset_tc $REP $REP2

function cleanup() {
    conntrack -F &>/dev/null
    ip netns del ns0 2> /dev/null
    ip netns del ns1 2> /dev/null
    reset_tc $REP $REP2
    killall -9 iperf3 &>/dev/null
    killall -9 tcpdump &>/dev/null

    #make sure ovs is running before setting config
    restart_openvswitch_nocheck
    ovs_conf_set hw-offload true

    start_clean_openvswitch
}
trap cleanup EXIT

function set_ipv6_rw_rules() {
    local field=$1

    ovs-ofctl del-flows br-ovs
    ovs-ofctl add-flow br-ovs "icmp6, actions=normal"
    ovs-ofctl add-flow br-ovs "table=0,in_port=$REP,tcp6, actions=ct(table=1)"
    ovs-ofctl add-flow br-ovs "table=0,in_port=$REP2,tcp6, actions=$field,ct(table=2),"
    ovs-ofctl add-flow br-ovs "table=1,in_port=$REP,tcp6, actions=ct(commit),$field,output:$REP2"
    ovs-ofctl add-flow br-ovs "table=2,in_port=$REP2,tcp6,ct_state=+trk+est actions=output:$REP"

    ovs-ofctl dump-flows br-ovs --color
}

function run_traffic_and_verify() {
    echo "Running iperf3 traffic for 2 seconds"
    ip netns exec ns1 timeout 5 iperf3 -s -1 &
    sleep 2

    ip netns exec ns0 timeout 5 iperf3 -c $IP2 -t 2 &
    sleep 1

    pidof iperf3 &>/dev/null || err "iperf3 failed"

    echo "Sniffing packets on $VF2"
    ip netns exec ns1 timeout 5 tcpdump -qnnei $VF2 -c 10 tcp &
    pid1=$!

    sleep 1
    echo "Datapath rules:"
    ovs-appctl dpctl/dump-flows

    sleep 4
    killall -9 iperf3 &>/dev/null
    wait $! 2>/dev/null

    title "Verifying traffic on $VF2"
    verify_have_traffic $pid1
}

function run() {
    title "Test OVS ipv6 tcp traffic with rewrite of ipv6 fields before and after CT"

    config_vf ns0 $VF $REP $IP1
    config_vf ns1 $VF2 $REP2 $IP2

    for d in $REP $REP2; do
        ethtool -k $d 2>/dev/null | grep -e "^rx-checksumming.*on" || fail "rx-checksumming disabled on dev $d"
    done

    echo "Setup ovs with hw offload false"
    ovs_conf_remove hw-offload
    restart_openvswitch_nocheck

    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs $REP2

    for f in "dec_ttl" "set_field:0x12345->ipv6_label" "mod_nw_tos:12"; do
        title "Test ipv6 checksum after rewrite action of field $f"
        set_ipv6_rw_rules $f
        run_traffic_and_verify
    done

    ovs-vsctl del-br br-ovs
}

cleanup
run
test_done
