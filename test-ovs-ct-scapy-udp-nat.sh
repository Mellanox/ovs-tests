#!/bin/bash
#
# Test OVS CT NAT udp traffic
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh
pktgen=$my_dir/scapy-traffic-tester.py

require_module act_ct

IP1="7.7.7.1"
IP2="7.7.7.2"
NAT_IP="7.7.7.101"

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
    ovs-ofctl1 add-flow ovs-br -O openflow13 "table=0,priority=100,ip,$PROTO,in_port=$VM1_PORT,action=set_field:$VM1_PORT->reg6,goto_table:5"
    ovs-ofctl1 add-flow ovs-br -O openflow13 "table=0,priority=100,ip,$PROTO,in_port=$VM2_PORT,action=set_field:$VM2_PORT->reg6,goto_table:5"

    ovs-ofctl1 add-flow ovs-br -O openflow13 "table=5,priority=100,ip,$PROTO,nw_dst=$NAT_IP,actions=move:NXM_OF_IP_DST[]->NXM_NX_XXREG0[0..31],move:NXM_OF_UDP_DST[]->NXM_NX_XXREG0[32..47],set_field:$VM2_IP->ip_dst,set_field:3005->${PROTO}_dst,set_field:0x1->reg11,ct(table=10,zone=NXM_NX_REG6[0..15])"
    ovs-ofctl1 add-flow ovs-br -O openflow13 "table=5,priority=100,ip,$PROTO,nw_dst=$VM1_IP,actions=ct(table=10,zone=NXM_NX_REG6[0..15])"

    ovs-ofctl1 add-flow ovs-br -O openflow13 "table=10,priority=100,ip,$PROTO,nw_dst=$VM2_IP,ct_state=-new+est-rel-inv+trk,actions=goto_table:15"
    ovs-ofctl1 add-flow ovs-br -O openflow13 "table=10,priority=100,ip,nw_dst=$VM2_IP,ct_state=+new-rel-inv+trk,actions=ct(commit,table=15,zone=NXM_NX_REG6[0..15],exec(move:NXM_NX_REG11[]->NXM_NX_CT_MARK[],move:NXM_NX_XXREG0[]->NXM_NX_CT_LABEL[]))"
    ovs-ofctl1 add-flow ovs-br -O openflow13 "table=10,priority=100,ip,nw_dst=$VM1_IP,ct_state=+new-est-rel-inv+trk,actions=ct(table=15,zone=NXM_NX_REG6[0..15])"
    ovs-ofctl1 add-flow ovs-br -O openflow13 "table=10,priority=100,ip,nw_dst=$VM1_IP,ct_state=-new+est-rel-inv+trk,actions=goto_table:15"

    ovs-ofctl1 add-flow ovs-br -O openflow13 "table=15,priority=100,ip,nw_dst=$VM1_IP,action=set_field:$VM1_PORT->reg7,goto_table:20"
    ovs-ofctl1 add-flow ovs-br -O openflow13 "table=15,priority=100,ip,nw_dst=$VM2_IP,action=set_field:$VM2_PORT->reg7,goto_table:20"

    ovs-ofctl1 add-flow ovs-br -O openflow13 "table=20,priority=100,ip,action=ct(table=25,zone=NXM_NX_REG7[0..15])"

    ovs-ofctl1 add-flow ovs-br -O openflow13 "table=25,priority=100,ip,nw_dst=$VM1_IP,ct_state=-new+est-rel-inv+trk,actions=move:NXM_NX_CT_MARK[]->NXM_NX_REG11[],move:NXM_NX_CT_LABEL[]->NXM_NX_XXREG0[],goto_table:30"
    ovs-ofctl1 add-flow ovs-br -O openflow13 "table=25,priority=100,ip,nw_dst=$VM2_IP,ct_state=+new-est-rel-inv+trk,actions=ct(commit,table=30,zone=NXM_NX_REG7[0..15])"
    ovs-ofctl1 add-flow ovs-br -O openflow13 "table=25,priority=100,ip,nw_dst=$VM2_IP,ct_state=-new+est-rel-inv+trk,actions=goto_table:30"

    ovs-ofctl1 add-flow ovs-br -O openflow13 "table=30,priority=100,ip,$PROTO,nw_dst=$VM2_IP,action=output:$VM2_PORT"
    ovs-ofctl1 add-flow ovs-br -O openflow13 "table=30,priority=100,ip,$PROTO,nw_dst=$VM1_IP,ct_state=-new+est-rel-inv+trk,actions=move:NXM_NX_XXREG0[0..31]->NXM_OF_IP_SRC[],move:NXM_NX_XXREG0[32..47]->NXM_OF_UDP_SRC[],output:$VM1_PORT"

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
    title "Test OVS CT NAT UDP"
    config_vf ns0 $VF $REP $IP1
    config_vf ns1 $VF2 $REP2 $IP2

    PROTO="udp"
    config_ovs

    t=10
    echo "sniff packets on $REP"
    timeout $t tcpdump -qnnei $REP -c 3 $PROTO &
    pid1=$!

    echo "run traffic for $t seconds"
    ip netns exec ns1 ip a add dev $VF2 $NAT_IP
    ip netns exec ns1 $pktgen -l -i $VF2 --src-ip $IP1 --time $((t+1)) &
    pk1=$!
    sleep 1
    ip netns exec ns0 $pktgen -i $VF1 --src-ip $IP1 --dst-ip $NAT_IP --time $t &
    pk2=$!

    # first 4 packets not offloaded until conn is in established state.
    sleep 2
    echo "sniff packets on $REP"
    timeout $t tcpdump -qnnei $REP -c 1 $PROTO &
    pid2=$!

    sleep $t
    kill $pk1 &>/dev/null
    wait $pk1 $pk2 2>/dev/null

    test_have_traffic $pid1
    test_no_traffic $pid2

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
