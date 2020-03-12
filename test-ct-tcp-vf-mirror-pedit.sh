#!/bin/bash
#
# Test CT fwd with vf mirror and pedit
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module act_ct
echo 1 > /proc/sys/net/netfilter/nf_conntrack_tcp_be_liberal

IP1="7.7.7.1"
IP2="7.7.7.2"

config_sriov 3
enable_switchdev_if_no_rep $REP
REP3=`get_rep 2`
require_interfaces REP REP2 REP3
unbind_vfs
bind_vfs
VF3=`get_vf 2`
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
    title "Test CT TCP VF mirror"
    config_vf ns0 $VF $REP $IP1
    config_vf ns1 $VF2 $REP2 $IP2
    ifconfig $VF3 0 up
    ifconfig $REP3 0 up

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
        action ct commit \
        action mirred egress mirror dev $REP3 pipe \
        action mirred egress redirect dev $REP2

    tc_filter add dev $REP ingress protocol ip chain 1 prio 2 flower \
        dst_mac $mac2 ct_state +trk+est \
        action mirred egress mirror dev $REP3 pipe \
        action pedit ex munge eth src set 20:22:33:44:55:66 pipe \
        action mirred egress redirect dev $REP2

    # reply chain0,ct -> chain1,fwd
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

    echo "run traffic"
    ip netns exec ns1 timeout 13 iperf -s &
    sleep 0.5
    ip netns exec ns0 timeout 13 iperf -t 12 -c $IP2 &

    sleep 2
    pidof iperf &>/dev/null || err "iperf failed"

    echo "sniff packets on $REP2"
    # first 4 packets not offloaded until conn is in established state.
    timeout 13 tcpdump -qnnei $REP2 -c 10 'tcp' &
    pid=$!
    
    echo "sniff packets on $VF3"
    timeout 13 tcpdump -qnnei $VF3 -c 10 'tcp' &
    pid2=$!

    sleep 13
    killall -9 iperf &>/dev/null
    wait $! 2>/dev/null

    # test offloaded
    wait $pid
    rc=$?
    if [[ $rc -eq 124 ]]; then
        :
    elif [[ $rc -eq 0 ]]; then
        err "Didn't expect to see packets"
    else
        err "Tcpdump failed"
    fi

    # test mirror port
    wait $pid2
    rc=$?
    if [[ $rc -eq 0 ]]; then
        :
    elif [[ $rc -eq 124 ]]; then
        err "Expected mirror packets"
    else
        err "Tcpdump mirror failed"
    fi

    reset_tc $REP
    reset_tc $REP2
    # wait for traces as merging & offloading is done in workqueue.
    sleep 3
}


start_check_syndrome
run
check_syndrome
test_done
