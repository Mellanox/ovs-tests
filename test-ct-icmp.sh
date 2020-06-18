#!/bin/bash
#
# Test CT fwd with icmp traffic
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module act_ct

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

function cleanup() {
    ip netns del ns0 2> /dev/null
    ip netns del ns1 2> /dev/null
    reset_tc $REP
    reset_tc $REP2
}
trap cleanup EXIT

function run() {
    title "Test CT ICMP"
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
        action ct commit \
        action mirred egress redirect dev $REP2

    tc_filter add dev $REP ingress protocol ip chain 1 prio 2 flower \
        dst_mac $mac2 ct_state +trk+est \
        action mirred egress redirect dev $REP2

    # chain0,ct -> chain1,fwd
    tc_filter add dev $REP2 ingress protocol ip prio 2 flower \
        dst_mac $mac1 \
        action ct action goto chain 1

    tc_filter add dev $REP2 ingress protocol ip prio 2 chain 1 flower \
        dst_mac $mac1 ct_state +trk+est \
        action mirred egress redirect dev $REP

    fail_if_err

    echo $REP
    tc filter show dev $REP ingress
    echo $REP2
    tc filter show dev $REP2 ingress

    echo "sniff packets on $REP"
    timeout 2 tcpdump -qnnei $REP -c 6 'icmp' &
    pid=$!

    echo "run traffic"
    ip netns exec ns0 ping -q -c 10 -i 0.1 -w 2 $IP2 || err "Ping failed"

    # test sniff timedout
    warn "Currently ICMP is not offloaded with CT so testing traffic is not offloaded so it will fail when is supported and update the test."
    wait $pid
    rc=$?
    if [[ $rc -eq 0 ]]; then
        success
    elif [[ $rc -eq 124 ]]; then
        err "Didn't expect offload"
    else
        err "Tcpdump failed"
    fi
}


start_check_syndrome
run
check_syndrome
test_done
