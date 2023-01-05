#!/bin/bash
#
# Test tc police mtu parameter which translates to hw RANGE_CHECK

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module act_police

IP1="7.7.7.1"
IP2="7.7.7.2"

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

    echo "add arp rules"
    tc_filter add dev $REP protocol arp parent ffff: prio 2 flower \
        action mirred egress redirect dev $REP2

    tc_filter add dev $REP2 protocol arp parent ffff: prio 2 flower \
        action mirred egress redirect dev $REP

    echo "add vf mtu rules"
    tc_filter add dev $REP prio 3 protocol ip parent ffff: \
        flower dst_ip $IP2 \
        action police mtu 1000  conform-exceed drop/pipe \
        mirred egress redirect dev $REP2

    tc_filter add dev $REP2 prio 3 protocol ip parent ffff: \
        flower dst_ip $IP1 \
        action mirred egress redirect dev $REP

    fail_if_err

    ip link show dev $REP
    tc filter show dev $REP ingress
    ip link show dev $REP2
    tc filter show dev $REP2 ingress
}

function test_ping() {
    local t=10
    timeout $((t-2)) tcpdump -qnnei $REP -c 1 icmp &
    local tpid=$!


    ip netns exec ns0 ping -c 3 -s 200  $IP2
    if [ $? -ne 0 ]; then
        echo $?
        err "ping failed"
        return
    fi

    ip netns exec ns0 ping -c 3 -s 1200 $IP2
    if [ $? -ne 1 ]; then
        err "packets greater than MTU condition were not dropped"
        return
    fi

    verify_no_traffic $tpid
}

function run() {
    title "Test police mtu action"

    config_police
    test_ping
}

run
trap - EXIT
cleanup
test_done
