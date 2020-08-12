#!/bin/bash
#
# Test CT with tcp traffic in NIC mode
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module act_ct

REMOTE_SERVER=${REMOTE_SERVER:-$1}
REMOTE_NIC=${REMOTE_NIC:-$2}

require_remote_server

disable_sriov
require_interfaces NIC NIC2
remote_disable_sriov
SRC_IP="7.7.7.1"
NAT_SRC="8.8.8.1"
REMOTE_IP="7.7.7.2"
REMOTE_IP2="8.8.8.2"
net=`getnet $REMOTE_IP2 24`

function cleanup() {
    on_remote "ip netns exec ns0 ip l s $REMOTE_NIC2 netns 1; ip netns del ns0; \
               ip addr flush $REMOTE_NIC; ip addr flush $REMOTE_NIC2" &>/dev/null

    ip addr flush $NIC
    ip addr flush $NIC2
}
trap cleanup EXIT

function get_pkts() {
    tc -j -p -s  filter show dev $NIC protocol ip ingress | jq '.[] | select(.options.keys.ct_state == "+trk+est") | .options.actions[0].stats.packets' || 0
}

function add_ct_rules() {
    echo "add ct rules"

    PF0=$NIC
    PF1=$NIC2
    PF0_MAC=`cat /sys/class/net/$NIC/address`
    PF1_MAC=`cat /sys/class/net/$NIC2/address`
    PF0_DEST_MAC=`on_remote cat /sys/class/net/$REMOTE_NIC/address` || err "Failed to get remote mac"
    PF1_DEST_MAC=`on_remote cat /sys/class/net/$REMOTE_NIC2/address` || err "Failed to get remote mac"

    fail_if_err

    tc_filter add dev $PF0 ingress prio 1 chain 0 proto ip flower ip_flags nofrag ip_proto tcp ct_state -trk \
        action ct zone 3 nat pipe action goto chain 2
    tc_filter add dev $PF0 ingress prio 1 chain 2 proto ip flower ip_flags nofrag ip_proto tcp ct_state +trk+new \
        action ct commit zone 3 nat src addr $NAT_SRC port 3000 pipe \
        action pedit ex munge ip ttl add 255 pipe \
        action pedit ex munge eth src set $PF1_MAC munge eth dst set $PF1_DEST_MAC pipe \
        action csum iph and tcp pipe \
        action mirred egress redirect dev $PF1
    tc_filter add dev $PF0 ingress prio 1 chain 2 proto ip flower ip_flags nofrag ip_proto tcp ct_state +trk+est \
        action pedit ex munge ip ttl add 255 pipe \
        action pedit ex munge eth src set $PF1_MAC munge eth dst set $PF1_DEST_MAC pipe \
        action csum iph and tcp pipe \
        action mirred egress redirect dev $PF1

    tc_filter add dev $PF1 ingress prio 1 chain 0 proto ip flower ip_flags nofrag ip_proto tcp ct_state -trk \
        action ct zone 3 nat pipe action goto chain 4
    tc_filter add dev $PF1 ingress prio 1 chain 4 proto ip flower ip_flags nofrag ip_proto tcp ct_state +trk+est \
        action pedit ex munge ip ttl add 255 pipe pedit ex munge eth src set $PF0_MAC munge eth dst set $PF0_DEST_MAC pipe \
        action csum iph and tcp pipe \
        action mirred egress redirect dev $PF0
}

function run() {
    title "Test CT TCP"
    tc_test_verbose
    reset_tc $NIC $NIC2

    title "config local"
    ip addr flush dev $NIC
    ip addr add dev $NIC $SRC_IP/24
    ip link set dev $NIC up

    ip addr flush dev $NIC2
    ip addr add dev $NIC2 $NAT_SRC/24
    ip link set dev $NIC2 up

    add_ct_rules
    fail_if_err

    echo $NIC
    tc filter show dev $NIC ingress
    echo $NIC2
    tc filter show dev $NIC2 ingress

    title "config remote"
    on_remote "ip addr add dev $REMOTE_NIC $REMOTE_IP/24; \
               ip link set dev $REMOTE_NIC up; \
               ip netns add ns0; \
               ip link set dev $REMOTE_NIC2 netns ns0; \
               ip -n ns0 addr add dev $REMOTE_NIC2 $REMOTE_IP2/24; \
               ip -n ns0 link set dev $REMOTE_NIC2 up; \
               ip route r $net via $SRC_IP"

    t=12
    title "run traffic for $t seconds"
    pkts1=`get_pkts`

    on_remote ip netns exec ns0 timeout $t tcpdump -qnnei $REMOTE_NIC2 -c 10 'tcp' &
    tpid1=$!

    on_remote ip netns exec ns0 timeout $((t+2)) iperf -s &
    sleep 1
    on_remote timeout $((t+1)) iperf -t $t -c $REMOTE_IP2 &

    sleep 2
    on_remote pidof iperf &>/dev/null || err "iperf failed"

    echo "sniff packets on $REP"
    # first 4 packets not offloaded until conn is in established state.
    timeout $t tcpdump -qnnei $NIC -c 10 'tcp' &
    tpid2=$!

    sleep $t
    on_remote killall -9 iperf &>/dev/null
    wait $! 2>/dev/null

    title "verify traffic started"
    verify_have_traffic $tpid1
    title "verify traffic offloaded"
    verify_no_traffic $tpid2

    title "verify tc stats"
    pkts2=`get_pkts`
    let a=pkts2-pkts1
    echo "pkts $a"
    if (( a < 50 )); then
        err "TC stats are not updated"
    fi

    reset_tc $NIC $NIC2
    # wait for traces as merging & offloading is done in workqueue.
    sleep 3
}


start_check_syndrome
cleanup
run
check_syndrome
test_done
