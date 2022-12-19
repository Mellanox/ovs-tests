#!/bin/bash
#
# Test tc action miss restore under stress
# Adds tc ct rules, and while creating new connections (new pkts go through SW),
# stresses the miss handling mechanisim in cls_api.c via concurrent add/dels.
#
# Feature #3226890: miss to action

my_dir="$(dirname "$0")"
. $my_dir/common.sh
pktgen=$my_dir/scapy-traffic-tester.py

require_module act_ct

IP1="7.7.7.1"
IP2="7.7.7.2"

config_sriov
enable_switchdev
require_interfaces REP REP2
unbind_vfs
bind_vfs
reset_tc $REP $REP2

mac2=`cat /sys/class/net/$VF2/address`
test "$mac2" || fail "no mac2"

function cleanup() {
    ip netns del ns0 2> /dev/null
    ip netns del ns1 2> /dev/null
    reset_tc $REP $REP2
}
trap cleanup EXIT

function run_traffic() {
    local rounds=$1
    local sport=$((RANDOM%1000+10000))
    local per_round=1000

    echo rounds: $rounds, sport: $sport, per_round: $per_round
    for i in `seq $rounds`; do
        local runtime=$((rounds-i+1))

        echo "round: $i/$rounds, per_round: $per_round, runtime: $runtime"
        ip netns exec ns0 ./scapy-traffic-tester.py -i $VF1 --src-ip 7.7.7.1 --dst-ip 7.7.7.2 \
            --time $runtime --src-port $((sport+per_round*i)) --src-port-count $per_round --dst-port 5201 --dst-port-count 1 --pkt-count 1 --inter 0 &>/dev/null &
        sleep 1
    done
}

function add_ct_rules() {
    local filter_actions="
        action pedit ex munge udp dport set 2048 pipe \
        action csum ip udp pipe \
        action ct action goto chain 1"

    #this tests deleting just a single handle, as prio 2 is held by another "handle 6" rule
    tc_filter add dev $REP ingress protocol ip prio 2 handle 5 flower $tc_verbose \
        dst_mac $mac2 ct_state -trk \
        ip_proto udp \
        $filter_actions

    #these match on different src_port suffixes , and would only match if prio 2 rule above is
    #delete. we delete these all at once.
    for i in `seq 0 15`; do
        tc_filter add dev $REP ingress protocol ip prio 3 handle $((100+i)) flower $tc_verbose \
        dst_mac $mac2 ct_state -trk \
        ip_proto udp src_port $i/15 \
        $filter_actions
    done
}

function del_ct_rules() {
    tc_filter del dev $REP ingress prio 2 handle 5 flower
    #sleep to let pkts hit prio 3
    sleep 0.5
    tc_filter del dev $REP ingress prio 3 flower
}

s1=$(( `date +%s` + 5 ))
num_rules=0
function play_with_rules() {
    del_ct_rules
    add_ct_rules

    let num_rules=num_rules+34
    (( `date +%s` > $s1 )) && echo "Added/Removed $num_rules rules." && s1=$(( `date +%s` + 5 ))
}

function show_nf_flow_table_conns() {
    while true; do
        sleep 5
        echo "Current connections in nf flow table: `cat /proc/net/nf_conntrack | grep 7.7.7 | wc -l`"
    done
}

function get_pkts() {
    # upstream tc dump
    s1=`tc -j -p -s  filter show dev $REP chain 1 prio 2 protocol ip ingress | jq '.[] | select(.options.keys.ct_state == "+trk+new") | .options.actions[0].stats.packets' || 0`

    echo $s1
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

    add_ct_rules

    #just to ref count prio 2, and when we remove prio 2 handle 5 above, prio 2 won't be deleted.
    tc_filter add dev $REP ingress protocol ip prio 2 handle 6 flower $tc_verbose \
        dst_mac aa:bb:cc:dd:ee:ff \
        action drop

    tc_filter add dev $REP ingress protocol ip chain 1 prio 2 flower $tc_verbose \
        dst_mac $mac2 ct_state +trk+new \
        action ct commit \
        action pedit ex munge udp dport set 5201 pipe \
        action csum ip udp pipe \
        action mirred egress redirect dev $REP2

    tc_filter add dev $REP ingress protocol ip chain 1 prio 3 flower $tc_verbose \
        dst_mac $mac2 ct_state +trk+est \
        action pedit ex munge udp dport set 5201 pipe \
        action csum ip udp pipe \
        action mirred egress redirect dev $REP2

    fail_if_err

    echo $REP
    tc filter show dev $REP ingress
    echo $REP2
    tc filter show dev $REP2 ingress

    #run_traffic runs for $rounds seconds
    local rounds=10
    run_traffic $rounds &
    pid=$!

    #show nf flow table connections every couple of seconds
    show_nf_flow_table_conns &
    pid2=$!

    pkts1=`get_pkts`

    #play with rules while waiting for run_traffic
    while `ps -p $pid > /dev/null`; do
        play_with_rules
    done

    title "verify tc sw stats"
    pkts2=`get_pkts`
    let a=pkts2-pkts1
    if (( a < 5 )); then
        err "TC stats are not updated"
    fi

    #kill background show_num_conns
    kill -9 $pid2 &>/dev/null

    #wait for ending prints from run_traffic
    sleep 5
}


run
trap - EXIT
cleanup
test_done
