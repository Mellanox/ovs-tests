#!/bin/bash
#
# Test OVS CT SNAT udp traffic
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh
pktgen=$my_dir/scapy-traffic-tester.py

require_module act_ct

IP1="7.7.7.1"
IP2="7.7.7.2"
NAT_IP="7.7.7.101"

PORT=6000
NAT_PORT=7000

enable_switchdev_if_no_rep $REP
require_interfaces REP REP2
unbind_vfs
bind_vfs
reset_tc $REP
reset_tc $REP2

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

function ovs-ofctl1 {
    local ofctl_err=0
    ovs-ofctl $@ || ofctl_err=1
    if [ $ofctl_err -ne 0 ]; then
        err "Command failed: ovs-ofctl $@"
    fi
}

function config_ovs_nat() {
    ovs-ofctl1 del-flows ovs-br
    ovs-ofctl1 add-flow ovs-br "arp,action=normal"
    
    ovs-ofctl1 add-flow ovs-br -O openflow13 "table=0,in_port=$VM1_PORT,ip,udp,action=ct(table=1,zone=1,nat)"
    ovs-ofctl1 add-flow ovs-br -O openflow13 "table=0,in_port=$VM2_PORT,ip,udp,ct_state=-trk,ip,action=ct(table=1,zone=1,nat)"

    ovs-ofctl1 add-flow ovs-br -O openflow13 "table=1,in_port=$VM1_PORT,ip,udp,ct_state=+trk+new,ct_zone=1,ip,action=ct(commit,nat(dst=$IP2:$NAT_PORT)),$VM2_PORT"
    ovs-ofctl1 add-flow ovs-br -O openflow13 "table=1,in_port=$VM1_PORT,ip,udp,ct_state=+trk+est,ct_zone=1,ip,action=$VM2_PORT"
    ovs-ofctl1 add-flow ovs-br -O openflow13 "table=1,in_port=$VM2_PORT,ip,udp,ct_state=+trk+est,ct_zone=1,ip,action=$VM1_PORT"

    fail_if_err "Failed to set ofctl rules"
}

function config_ovs() {
    echo "setup ovs"
    start_clean_openvswitch
    ovs-vsctl add-br ovs-br
    ovs-vsctl add-port ovs-br $REP
    ovs-vsctl add-port ovs-br $REP2

    VM1_IP=$IP1
    VM1_PORT=`ovs-vsctl list interface $REP | grep "ofport\s*:" | awk {'print $3'}`
    VM2_IP=$IP2
    VM2_PORT=`ovs-vsctl list interface $REP2 | grep "ofport\s*:" | awk {'print $3'}`

    ovs-ofctl add-flow ovs-br in_port=$REP,dl_type=0x0806,actions=output:$REP2
    ovs-ofctl add-flow ovs-br in_port=$REP2,dl_type=0x0806,actions=output:$REP

    config_ovs_nat
    ovs-ofctl dump-flows ovs-br --color
}

function run() {
    title "Test OVS CT DNAT UDP"
    config_vf ns0 $VF $REP $IP1
    config_vf ns1 $VF2 $REP2 $IP2
    conntrack -F

    PROTO="udp"
    config_ovs

    t=10
    echo "sniff packets on $REP"
    timeout $t tcpdump -qnnei $REP -c 3 $PROTO &
    pid1=$!

    echo "run traffic for $t seconds"
    ip netns exec ns1 ip a add dev $VF2 $NAT_IP
    ip netns exec ns1 $pktgen -l -i $VF2 --src-ip $IP1 --time $((t+2)) &
    pk1=$!
    sleep 1
    ip netns exec ns0 $pktgen -i $VF1 --src-ip $IP1 --dst-ip $NAT_IP --dst-port $PORT --time $t &
    pk2=$!

    # first 4 packets not offloaded until conn is in established state.
    sleep 2
    echo "sniff packets on $REP"
    timeout $t tcpdump -qnnei $REP -c 1 $PROTO &
    pid2=$!

    # Make sure NAT works as expected
    timeout $t ip netns exec ns0 tcpdump -qnnei $VF1 -c 4 src $NAT_IP and src port $PORT &
    pid3=$!
    timeout $t ip netns exec ns1 tcpdump -qnnei $VF2 -c 4 dst $IP2 and dst port $NAT_PORT &
    pid4=$!

    title "Check for dnat rule"
    ovs_dump_tc_flows --names
    ovs_dump_tc_flows --names | grep -q "nat(dst="
    if [ $? -eq 0 ]; then
        success
    else
        err "Missing dnat rule"
    fi

    sleep $t
    kill $pk1 &>/dev/null
    wait $pk1 $pk2 2>/dev/null
 
    title "Verify traffic offloaded"
    test_have_traffic $pid1
    test_no_traffic $pid2
    
    title "Verify nat traffic on $VF1"
    test_have_traffic $pid3
    title "Verify nat traffic on $VF2"
    test_have_traffic $pid4

    ovs-vsctl del-br ovs-br

    # wait for traces as merging & offloading is done in workqueue.
    sleep 3
}

function test_have_traffic() {
    local pid=$1
    wait $pid
    rc=$?
    if [[ $rc -eq 0 ]]; then
        :
    elif [[ $rc -eq 124 ]]; then
        err "Expected to see packets"
    else
        err "Tcpdump failed"
    fi
}

function test_no_traffic() {
    local pid=$1
    wait $pid
    rc=$?
    if [[ $rc -eq 124 ]]; then
        :
    elif [[ $rc -eq 0 ]]; then
        err "Didn't expect to see packets"
    else
        err "Tcpdump failed"
    fi
}


run
test_done
