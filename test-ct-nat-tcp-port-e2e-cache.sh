#!/bin/bash
#
# Test CT ipv4 NAT with tcp traffic
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module act_ct
require_module e2e_cache
modprobe e2e_cache

IP1="7.7.7.1"
IP2="7.7.7.2"
IP3="7.7.7.3"

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
    title "Test CT nat tcp"
    tc_test_verbose
    config_vf ns0 $VF $REP $IP1
    config_vf ns1 $VF2 $REP2 $IP2
    ip -netns ns0 neigh replace $IP3 dev $VF lladdr $mac2
    ip -netns ns1 neigh replace $IP1 dev $VF2 lladdr $mac1

    flag=""
    # use this flag to test miss handling
    #flag2="skip_hw"

    echo "add ct rules"
    tc_filter add dev $REP ingress protocol ip prio 2 flower $flag $tc_verbose \
        dst_mac $mac2 ct_state -trk \
        action ct nat action goto chain 1

    tc_filter add dev $REP ingress protocol ip chain 1 prio 2 flower $flag $tc_verbose \
        dst_mac $mac2 ct_state +trk+new \
        action ct commit nat dst addr $IP2 port 6001\
        action mirred egress redirect dev $REP2

    tc_filter add dev $REP ingress protocol ip chain 1 prio 2 flower $flag $flag2 $tc_verbose \
        dst_mac $mac2 ct_state +trk+est \
        action mirred egress redirect dev $REP2

    # chain0,ct -> chain1,fwd
    tc_filter add dev $REP2 ingress protocol ip prio 2 flower $flag $tc_verbose \
        dst_mac $mac1 ct_state -trk \
        action ct nat action goto chain 1

    tc_filter add dev $REP2 ingress protocol ip prio 2 chain 1 flower $flag $flag2 $tc_verbose \
        dst_mac $mac1 ct_state +trk+est \
        action mirred egress redirect dev $REP

    fail_if_err

    echo $REP
    tc filter show dev $REP ingress
    echo $REP2
    tc filter show dev $REP2 ingress

    t=15
    echo "run traffic for $t seconds"
    ip netns exec ns1 timeout $((t+7)) iperf -s -p 6001 &
    sleep 2

    ip netns exec ns0 timeout $((t+2)) iperf -t $t -c $IP3 -P 1 -i 1 &

    sleep 2
    pidof iperf &>/dev/null || err "iperf failed"

    echo "sniff packets on $VF2"
    ip netns exec ns1 timeout $t tcpdump -qnnei $VF2 -c 10 'tcp' &
    pid1=$!

    echo "sniff packets on $REP"
    # first 4 packets not offloaded until conn is in established state.
    timeout $t tcpdump -qnnei $REP -c 10 'tcp' &
    pid=$!

    sleep $t
    killall -9 iperf &>/dev/null
    wait $! 2>/dev/null

    title "verify traffic on $VF2"
    verify_have_traffic $pid1

    title "verify traffic offloaded on $REP"
    verify_no_traffic $pid

    for i in $REP $REP2; do
        title e2e_cache $i
        tc_filter show dev $i ingress e2e_cache
        tc_filter show dev $i ingress e2e_cache | grep -q handle
        if [ "$?" != 0 ]; then
            err "Expected e2e_cache rule"
        fi
        if [ "$i" == "$REP" ]; then
            tc_filter show dev $i ingress e2e_cache | grep -q pedit
            if [ "$?" != 0 ]; then
                err "Expected e2e_cache pedit rule"
            fi
        fi
    done

    reset_tc $REP $REP2
}


start_check_syndrome
run
check_syndrome
test_done
