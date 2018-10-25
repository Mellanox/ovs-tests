#!/bin/bash
#
# Test CT fwd with icmp traffic and rule ct+fwd
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

IP1="7.7.7.1"
IP2="7.7.7.2"

config_sriov 3
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
    tc_filter add dev $REP ingress protocol ip prio 2 flower \
        dst_mac $mac2 ct_state -trk \
        action ct action goto chain 1

    tc_filter add dev $REP ingress protocol ip chain 1 prio 2 flower \
        dst_mac $mac2 ct_state +trk+new \
        action mirred egress redirect dev $REP2

    tc_filter add dev $REP ingress protocol ip chain 1 prio 2 flower \
        dst_mac $mac2 ct_state +trk+est \
        action mirred egress redirect dev $REP2

    # test action ct+fwd
    tc_filter add dev $REP2 ingress protocol ip prio 2 flower \
        dst_mac $mac1 \
        action ct \
        action mirred egress redirect dev $REP

    fail_if_err

    echo $REP
    tc filter show dev $REP ingress

    echo "sniff packets on $REP"
    timeout 2 tcpdump -qnei $REP -c 6 'icmp' &
    pid=$!

    echo "run traffic"
    ip netns exec ns0 ping -q -c 10 -i 0.1 -w 1 $IP2 || err "Ping failed"

    wait $pid
    # test sniff timedout
    # currently ICMP is not offloaded with CT
    # so test its not offloaded so we will fail and update the test when
    # offloading will be supported.
    rc=$?
    if [[ $rc -eq 0 ]]; then
        success
    elif [[ $rc -eq 124 ]]; then
        err "Didn't expect offload"
    else
        err "Tcpdump failed"
    fi
}


run
test_done
