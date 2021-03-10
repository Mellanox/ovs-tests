#!/bin/bash
#
# Test CT fwd with udp traffic
# test with changing zone in a chain
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh
pktgen=$my_dir/scapy-traffic-tester.py

require_module act_ct
require_module e2e_cache
modprobe e2e_cache

IP1="7.7.7.1"
IP2="7.7.7.2"

enable_switchdev
require_interfaces REP REP2
unbind_vfs
bind_vfs
reset_tc_cacheable $REP $REP2

mac1=`cat /sys/class/net/$VF/address`
mac2=`cat /sys/class/net/$VF2/address`

test "$mac1" || fail "no mac1"
test "$mac2" || fail "no mac2"

function cleanup() {
    ip netns del ns0 2> /dev/null
    ip netns del ns1 2> /dev/null
    reset_tc $REP
    reset_tc $REP2
}
trap cleanup EXIT

function run() {
    title "Test CT"
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
        action ct action goto chain 1

    tc_filter add dev $REP ingress protocol ip chain 1 prio 2 flower $tc_verbose \
        dst_mac $mac2 ct_state +trk+new \
        action ct commit action goto chain 2

    tc_filter add dev $REP ingress protocol ip chain 1 prio 2 flower $tc_verbose \
        dst_mac $mac2 ct_state +trk+est action goto chain 2

    tc_filter add dev $REP ingress protocol ip chain 2 prio 2 flower $tc_verbose \
        dst_mac $mac2 \
        action ct zone 3 action goto chain 3

    tc_filter add dev $REP ingress protocol ip chain 3 prio 2 flower $tc_verbose \
        dst_mac $mac2 ct_state +trk+new \
        action ct zone 3 commit \
        action mirred egress redirect dev $REP2

    tc_filter add dev $REP ingress protocol ip chain 3 prio 2 flower $tc_verbose \
        dst_mac $mac2 ct_state +trk+est \
        action mirred egress redirect dev $REP2

    # chain0,ct -> chain1,fwd
    tc_filter add dev $REP2 ingress protocol ip prio 2 flower $tc_verbose \
        dst_mac $mac1 \
        action ct action goto chain 1

    tc_filter add dev $REP2 ingress protocol ip prio 2 chain 1 flower $tc_verbose \
        dst_mac $mac1 ct_state +trk+est action ct zone 3 goto chain 2

    tc_filter add dev $REP2 ingress protocol ip prio 2 chain 2 flower $tc_verbose \
        dst_mac $mac1 ct_state +trk+est \
        action mirred egress redirect dev $REP

    fail_if_err

    echo $REP
    tc filter show dev $REP ingress
    echo $REP2
    tc filter show dev $REP2 ingress

    t=12
    echo "run traffic for $t seconds"
    ip netns exec ns1 $pktgen -l -i $VF2 --src-ip $IP1 --time 10 &
    pk1=$!
    sleep 2
    ip netns exec ns0 $pktgen -i $VF1 --src-ip $IP1 --dst-ip $IP2 --time 2 --inter 1 --pkt-count 1 &
    pk2=$!

    sleep 10
    kill $pk1 &>/dev/null
    wait $pk1 $pk2 2>/dev/null

    tc -s filter show dev $REP ingress
    conntrack -L | grep $IP1
    echo

    for i in $REP $REP2; do
        title e2e_cache $i
        tc_filter show dev $i ingress e2e_cache
        tc_filter show dev $i ingress e2e_cache | grep -q handle
        if [ "$?" != 0 ]; then
            err "Expected e2e_cache rule"
        fi
    done

# delete filter case
#    tc filter del prio 2 dev $REP ingress
#    tc filter del prio 2 dev $REP2 ingress

# delete qdisc case
    reset_tc $REP $REP2
}


start_check_syndrome
run
check_syndrome
test_done
