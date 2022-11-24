#!/bin/bash
#
# Test CT + tuple header rewrite
# we have a miss in CT for the new connection, but we already did the pedit before CT.
# so we can't continue from chain 0, instead we continue from the action CT in the action list.
# so we do the CT again in SW, and goto chain that follows.
#
# Feature #3226890: miss to action

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module act_ct
echo 1 > /proc/sys/net/netfilter/nf_conntrack_tcp_be_liberal

IP1="7.7.7.1"
IP2="7.7.7.2"

config_sriov
enable_switchdev
require_interfaces REP REP2
unbind_vfs
bind_vfs
reset_tc $REP $REP2

mac1=`cat /sys/class/net/$VF/address`
mac2=`cat /sys/class/net/$VF2/address`

test "$mac1" || fail "no mac1"
test "$mac2" || fail "no mac2"

function cleanup() {
    ip netns del ns0 2> /dev/null
    ip netns del ns1 2> /dev/null
    reset_tc $REP $REP2
}
trap cleanup EXIT

function get_est_pkts() {
    # single table tc show doesn't have nested keys attribute
    s1=`tc -j -p -s  filter show dev $REP protocol ip ingress | jq '.[] | select(.options.ct_state == "+trk+est") | .options.actions[0].stats.packets' || 0`
    # upstream tc dump
    s2=`tc -j -p -s  filter show dev $REP protocol ip ingress | jq '.[] | select(.options.keys.ct_state == "+trk+est") | .options.actions[0].stats.packets' || 0`

    echo $(( s1 > s2 ? s1 : s2 ))
}

function run() {
    title "Test CT TCP"
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
        action pedit ex munge tcp dport set 2048 pipe \
        action csum ip tcp pipe \
        action ct action goto chain 1

    tc_filter add dev $REP ingress protocol ip chain 1 prio 2 flower $tc_verbose \
        dst_mac $mac2 ct_state +trk+new \
        action ct commit \
        action pedit ex munge tcp dport set 5201 pipe \
        action csum ip tcp pipe \
        action mirred egress redirect dev $REP2

    tc_filter add dev $REP ingress protocol ip chain 1 prio 2 flower $tc_verbose \
        dst_mac $mac2 ct_state +trk+est \
        action pedit ex munge tcp dport set 5201 pipe \
        action csum ip tcp pipe \
        action mirred egress redirect dev $REP2

    # chain0,ct -> chain1,fwd
    tc_filter add dev $REP2 ingress protocol ip prio 2 flower $tc_verbose \
        dst_mac $mac1 \
        action pedit ex munge tcp sport set 2048 pipe \
        action csum ip tcp pipe \
        action ct action goto chain 1

    tc_filter add dev $REP2 ingress protocol ip prio 2 chain 1 flower $tc_verbose \
        dst_mac $mac1 ct_state +trk+est \
        action pedit ex munge tcp sport set 5201 pipe \
        action csum ip tcp pipe \
        action mirred egress redirect dev $REP

    fail_if_err

    echo $REP
    tc filter show dev $REP ingress
    echo $REP2
    tc filter show dev $REP2 ingress

    t=12
    echo "run traffic for $t seconds"
    ip netns exec ns1 iperf3 -s -D
    ip netns exec ns0 timeout $((t+1)) iperf3 -t $t -c $IP2 -P 3 &

    sleep 2
    pidof iperf3 &>/dev/null || err "iperf3 failed"

    echo "sniff packets on $REP"
    # first 4 packets not offloaded until conn is in established state.
    timeout $((t-4)) tcpdump -qnnei $REP -c 10 'tcp' &
    pid=$!

    pkts1=`get_est_pkts`

    sleep $t
    killall -9 iperf3 &>/dev/null
    wait $! 2>/dev/null

    title "verify tc stats"
    pkts2=`get_est_pkts`
    let a=pkts2-pkts1
    if (( a < 5 )); then
        err "TC stats are not updated"
    fi

    hw_pkts=`tc -p -s -j  filter show dev $REP protocol ip ingress chain 0 prio 2 | jq '.[] | select(.options.handle) | .options.actions[0].stats.hw_packets' || 0`
    sw_pkts=`tc -p -s -j  filter show dev $REP protocol ip ingress chain 0 prio 2 | jq '.[] | select(.options.handle) | .options.actions[0].stats.sw_packets' || 0`
    tot_pkts=`tc -p -s -j  filter show dev $REP protocol ip ingress chain 0 prio 2 | jq '.[] | select(.options.handle) | .options.actions[0].stats.packets' || 0`
    (( $hw_pkts == $tot_pkts )) && (( $sw_pkts  == 0 )) || err "Not all chain 0 packets were offloaded on dev $REP"

    title "Verify no traffic on $REP"
    verify_no_traffic $pid
}


run
trap - EXIT
cleanup
test_done
