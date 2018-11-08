#!/bin/bash
#
# Test CT fwd with pedit and tcp traffic
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_act_ct

IP1="7.7.7.1"
IP2="7.7.7.2"

enable_switchdev_if_no_rep $REP
require_interfaces REP REP2
unbind_vfs
bind_vfs
reset_tc $REP
reset_tc $REP2

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

function config_vf() {
    local ns=$1
    local vf=$2
    local rep=$3
    local ip=$4

    echo "[$ns] $vf ($ip) -> $rep"
    ifconfig $rep 0 up
    ip netns add $ns
    ip link set $vf netns $ns
    ip netns exec $ns ifconfig $vf $ip/24 up
}

function run() {
    title "Test VF Mirror"
    config_vf ns0 $VF $REP $IP1
    config_vf ns1 $VF2 $REP2 $IP2

    echo "add arp rules"
    tc_filter add dev $REP ingress protocol arp prio 1 flower \
        action mirred egress redirect dev $REP2

    tc_filter add dev $REP2 ingress protocol arp prio 1 flower \
        action mirred egress redirect dev $REP

    echo "add ct rules"
    # req
    tc_filter add dev $REP ingress protocol ip prio 2 flower \
        dst_mac $mac2 ct_state -trk \
        action ct action goto chain 1

    tc_filter add dev $REP ingress protocol ip chain 1 prio 2 flower \
        dst_mac $mac2 ct_state +trk+new \
        action pedit ex munge eth src set 20:22:33:44:55:66 pipe \
        action mirred egress redirect dev $REP2

    tc_filter add dev $REP ingress protocol ip chain 1 prio 2 flower \
        dst_mac $mac2 ct_state +trk+est \
        action mirred egress redirect dev $REP2

    # reply chain0,ct -> chain1,fwd
    tc_filter add dev $REP2 ingress protocol ip prio 2 flower \
        dst_mac $mac1 \
        action ct action goto chain 1

    tc_filter add dev $REP2 ingress protocol ip prio 2 chain 1 flower \
        action mirred egress redirect dev $REP

    fail_if_err

    echo $REP
    tc filter show dev $REP ingress
    echo $REP2
    tc filter show dev $REP2 ingress

    echo "run traffic"
    ip netns exec ns1 timeout 6 iperf -s &
    ip netns exec ns0 timeout 6 iperf -t 5 -c $IP2 &

    echo "sniff packets on $REP2"
    sleep 1
    # first 4 packets not offloaded until conn is in established state.
    timeout 2 tcpdump -qnnei $REP2 -c 10 'tcp' &
    pid=$!

    sleep 6
    killall -9 iperf &>/dev/null
    wait $! 2>/dev/null

    wait $pid
    # test sniff timedout
    rc=$?
    if [[ $rc -eq 124 ]]; then
        :
    elif [[ $rc -eq 0 ]]; then
        err "Didn't expect to see packets"
    else
        err "Tcpdump failed"
    fi

    reset_tc $REP
    reset_tc $REP2
    # wait for traces as merging & offloading is done in workqueue.
    sleep 3
}


run
test_done
