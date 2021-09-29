#!/bin/bash
#
# Test CT and meter with udp traffic
# Bug SW #2707092, metering doesn't work before version xx.31.0354 xx.32.0114

my_dir="$(dirname "$0")"
. $my_dir/common.sh

not_relevant_for_nic cx4 cx4lx cx5

require_module act_ct act_police

IP1="7.7.7.1"
IP2="7.7.7.2"

enable_switchdev
require_interfaces REP REP2
unbind_vfs
bind_vfs
reset_tc $REP
reset_tc $REP2

mac1=`cat /sys/class/net/$VF/address`
mac2=`cat /sys/class/net/$VF2/address`

test "$mac1" || fail "no mac1"
test "$mac2" || fail "no mac2"

RATE=200
BURST=65536
TMPFILE=/tmp/meter.log

function cleanup() {
    ip netns del ns0 2> /dev/null
    ip netns del ns1 2> /dev/null
    reset_tc $REP
    reset_tc $REP2
}
trap cleanup EXIT

function run() {
    title "Test CT with police action by UDP traffic"
    tc_test_verbose
    config_vf ns0 $VF $REP $IP1
    config_vf ns1 $VF2 $REP2 $IP2

    echo "add arp rules"
    tc_filter add dev $REP ingress protocol arp prio 1 flower $tc_verbose \
        action mirred egress redirect dev $REP2

    tc_filter add dev $REP2 ingress protocol arp prio 1 flower $tc_verbose \
        action mirred egress redirect dev $REP

    echo "add ct rules"
    tc_filter add dev $REP ingress protocol ip prio 2 flower $tc_verbose \
        dst_mac $mac2 ct_state -trk \
        action ct \
        action police rate ${RATE}mbit burst $BURST conform-exceed drop/pipe \
        action goto chain 1

    tc_filter add dev $REP ingress protocol ip chain 1 prio 2 flower $tc_verbose \
        dst_mac $mac2 ct_state +trk+new \
        action ct commit \
        action mirred egress redirect dev $REP2

    tc_filter add dev $REP ingress protocol ip chain 1 prio 2 flower $tc_verbose \
        dst_mac $mac2 ct_state +trk+est \
        action mirred egress redirect dev $REP2

    # chain0,ct -> chain1,fwd
    tc_filter add dev $REP2 ingress protocol ip prio 2 flower $tc_verbose \
        dst_mac $mac1 \
        action ct action goto chain 1

    tc_filter add dev $REP2 ingress protocol ip prio 2 chain 1 flower $tc_verbose \
        dst_mac $mac1 ct_state +trk+est \
        action mirred egress redirect dev $REP

    fail_if_err

    t=12
    echo "run traffic for $t seconds"
    ip netns exec ns1 timeout $((t+1)) iperf3 -s &
    sleep 0.5
    ip netns exec ns0 timeout $((t+1)) iperf3 -t $t -c $IP2 -u -b 2G > $TMPFILE &

    sleep 2
    pidof iperf3 &>/dev/null || err "iperf3 failed"

    echo "sniff packets on $REP"
    # first 4 packets not offloaded until conn is in established state.
    timeout $((t-4)) tcpdump -qnnei $REP -c 10 'udp' &
    pid=$!

    sleep $t
    killall -9 iperf3 &>/dev/null
    wait $! 2>/dev/null

    title "verify traffic offloaded"
    verify_no_traffic $pid

    rate=`cat $TMPFILE | grep "receiver" | sed  "s/\[.*Bytes//" | sed "s/ Mbits.*//"`
    title "verify rate"
    verify_rate $rate $RATE

    reset_tc $REP
    reset_tc $REP2
}


start_check_syndrome
run
check_syndrome
check_kasan
test_done
