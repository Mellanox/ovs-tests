#!/bin/bash
#
# Test act_police jump control


my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module act_police

IP1="7.7.7.1"
IP2="7.7.7.2"
RATE=5

TMPFILE=/tmp/iperf3.log

min_nic_cx6
config_sriov 2
enable_switchdev
require_interfaces REP REP2
unbind_vfs
bind_vfs

function cleanup() {
    ip netns del ns0
    ip netns del ns1
    reset_tc $REP $REP2
    sleep 0.5
    tc action flush action police
}
trap cleanup EXIT

function config_police() {
    config_vf ns0 $VF $REP $IP1
    config_vf ns1 $VF2 $REP2 $IP2
    reset_tc $REP $REP2

    tc action flush action police
    tc action add police rate ${RATE}mbit burst 1m conform-exceed pipe / jump 2

    echo "add arp rules"
    tc_filter add dev $REP protocol arp parent ffff: prio 1 flower \
        action mirred egress redirect dev $REP2

    tc_filter add dev $REP2 protocol arp parent ffff: prio 1 flower \
        action mirred egress redirect dev $REP

    echo "add vf meter rules"
    tc_filter add dev $REP prio 2 protocol ip parent ffff: \
        flower ip_proto tcp dst_ip $IP2 \
        action police index 1 \
        action drop \
        mirred egress redirect dev $REP2

    tc_filter add dev $REP2 prio 2 protocol ip parent ffff: \
        flower ip_proto tcp dst_ip $IP1 \
        action police index 1 \
        action drop \
        mirred egress redirect dev $REP

    fail_if_err

    ip link show dev $REP
    tc filter show dev $REP ingress
    ip link show dev $REP2
    tc filter show dev $REP2 ingress
}

function test_tcp() {
    title "Test iperf3 tcp $VF($IP1) -> $VF2($IP2)"
    ip netns exec ns1 timeout 11 iperf3 -s -D
    sleep 0.5
    ip netns exec ns0 timeout 11 iperf3 -c $IP2 -t 10 -J c -P2 > $TMPFILE &
    sleep 11
    killall -9 iperf3 &>/dev/null
    sleep 0.5
}

function run() {
    title "Test act_police action"

    config_police
    test_tcp

    verify_iperf3_bw $TMPFILE $RATE
}

run
trap - EXIT
cleanup
test_done
