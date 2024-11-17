#!/bin/bash
#
# Test OVS CT NAT udp traffic and reconfig ct rules during traffic
# This is a fake nat using registers.
#
# Bug SW #1610340: syndrome and kernel crash when we reconfig ct rules during traffic
#
# This test is relevant for ST CT and not MT CT. traffic won't be offloaded in MT CT.
# Bug SW #2115017: [Upstream][CT] CT label with more than 32 bit is not supported

my_dir="$(dirname "$0")"
. $my_dir/common.sh
pktgen=$my_dir/scapy-traffic-tester.py

add_expected_error_msg "recirc_id .* left allocated when ofproto"

require_module act_ct

IP1="7.7.7.1"
IP2="7.7.7.2"
NAT_IP="7.7.7.101"

enable_switchdev
require_interfaces REP REP2
unbind_vfs
bind_vfs
reset_tc $REP
reset_tc $REP2

function cleanup() {
    ovs_clear_bridges &>/dev/null
    ip netns del ns0 2> /dev/null
    ip netns del ns1 2> /dev/null
    reset_tc $REP
    reset_tc $REP2
}
trap cleanup EXIT

ofctl_err=0
function ovs-ofctl1 {
    ovs-ofctl $1 $2 $3 $4 "$5" || ofctl_err=1
    if [ $ofctl_err -ne 0 ]; then
        err "Command failed: ovs-ofctl $@"
    fi
}

function config_ovs_nat() {
    VM1_IP=$IP1
    VM1_PORT=`ovs-vsctl list interface $REP | grep "ofport\s*:" | awk {'print $3'}`
    VM2_IP=$IP2
    VM2_PORT=`ovs-vsctl list interface $REP2 | grep "ofport\s*:" | awk {'print $3'}`
    ovs-ofctl1 del-flows ovs-br
    ovs-ofctl add-flow ovs-br "arp,action=normal"
    ovs-ofctl1 add-flow ovs-br -O openflow13 "table=0,priority=100,ip,$PROTO,in_port=$VM1_PORT,action=set_field:$VM1_PORT->reg6,goto_table:5"
    ovs-ofctl1 add-flow ovs-br -O openflow13 "table=0,priority=100,ip,$PROTO,in_port=$VM2_PORT,action=set_field:$VM2_PORT->reg6,goto_table:5"

    ovs-ofctl1 add-flow ovs-br -O openflow13 "table=5,priority=100,ip,$PROTO,nw_dst=$NAT_IP,actions=move:NXM_OF_IP_DST[]->NXM_NX_XXREG0[0..31],move:NXM_OF_UDP_DST[]->NXM_NX_XXREG0[32..47],set_field:$VM2_IP->ip_dst,set_field:3005->${PROTO}_dst,set_field:0x1->reg11,ct(table=10,zone=NXM_NX_REG6[0..15])"
    ovs-ofctl1 add-flow ovs-br -O openflow13 "table=5,priority=100,ip,$PROTO,nw_dst=$VM1_IP,actions=ct(table=10,zone=NXM_NX_REG6[0..15])"

    ovs-ofctl1 add-flow ovs-br -O openflow13 "table=10,priority=100,ip,$PROTO,nw_dst=$VM2_IP,ct_state=-new+est-rel-inv+trk actions=goto_table:15"
    ovs-ofctl1 add-flow ovs-br -O openflow13 "table=10,priority=100,ip,nw_dst=$VM2_IP,ct_state=+new-rel-inv+trk actions=ct(commit,table=15,zone=NXM_NX_REG6[0..15],exec(move:NXM_NX_REG11[]->NXM_NX_CT_MARK[],move:NXM_NX_XXREG0[]->NXM_NX_CT_LABEL[]))"
    ovs-ofctl1 add-flow ovs-br -O openflow13 "table=10,priority=100,ip,nw_dst=$VM1_IP,ct_state=+new-est-rel-inv+trk actions=ct(table=15,zone=NXM_NX_REG6[0..15])"
    ovs-ofctl1 add-flow ovs-br -O openflow13 "table=10,priority=100,ip,nw_dst=$VM1_IP,ct_state=-new+est-rel-inv+trk actions=goto_table:15"

    ovs-ofctl1 add-flow ovs-br -O openflow13 "table=15,priority=100,ip,nw_dst=$VM1_IP,action=set_field:$VM1_PORT->reg7,goto_table:20"
    ovs-ofctl1 add-flow ovs-br -O openflow13 "table=15,priority=100,ip,nw_dst=$VM2_IP,action=set_field:$VM2_PORT->reg7,goto_table:20"

    ovs-ofctl1 add-flow ovs-br -O openflow13 "table=20,priority=100,ip,action=ct(table=25,zone=NXM_NX_REG7[0..15])"

    ovs-ofctl1 add-flow ovs-br -O openflow13 "table=25,priority=100,ip,nw_dst=$VM1_IP,ct_state=-new+est-rel-inv+trk actions=move:NXM_NX_CT_MARK[]->NXM_NX_REG11[],move:NXM_NX_CT_LABEL[]->NXM_NX_XXREG0[],goto_table:30"
    ovs-ofctl1 add-flow ovs-br -O openflow13 "table=25,priority=100,ip,nw_dst=$VM2_IP,ct_state=+new-est-rel-inv+trk actions=ct(commit,table=30,zone=NXM_NX_REG7[0..15])"
    ovs-ofctl1 add-flow ovs-br -O openflow13 "table=25,priority=100,ip,nw_dst=$VM2_IP,ct_state=-new+est-rel-inv+trk actions=goto_table:30"

    ovs-ofctl1 add-flow ovs-br -O openflow13 "table=30,priority=100,ip,$PROTO,nw_dst=$VM2_IP,action=output:$VM2_PORT"
    ovs-ofctl1 add-flow ovs-br -O openflow13 "table=30,priority=100,ip,$PROTO,nw_dst=$VM1_IP,ct_state=-new+est-rel-inv+trk actions=move:NXM_NX_XXREG0[0..31]->NXM_OF_IP_SRC[],move:NXM_NX_XXREG0[32..47]->NXM_OF_UDP_SRC[],output:$VM1_PORT"

    if [ $ofctl_err -ne 0 ]; then
        fail "Failed to set ofctl rules"
    fi
}

function config_ovs() {
    echo "setup ovs"
    start_clean_openvswitch
    ovs-vsctl add-br ovs-br
    ovs-vsctl add-port ovs-br $REP
    ovs-vsctl add-port ovs-br $REP2
    config_ovs_nat
    ovs-ofctl dump-flows ovs-br --color
}

function run() {
    title "Test OVS CT NAT UDP"
    config_vf ns0 $VF $REP $IP1
    config_vf ns1 $VF2 $REP2 $IP2

    PROTO="udp"
    config_ovs

    local start1=`get_time`
    t=30
    port_count=100
    port_count2=30

    echo "run traffic for $t seconds"
    ip netns exec ns1 ip a add dev $VF2 $NAT_IP
    ip netns exec ns1 $pktgen -l -i $VF2 --src-ip $IP1 --time $((t+1)) --src-port-count $port_count &
    pk1=$!
    sleep 2
    ip netns exec ns0 $pktgen -i $VF1 --src-ip $IP1 --dst-ip $NAT_IP --time $t --src-port-count $port_count --dst-port-count $port_count2 --pkt-count 1 --inter 0 &
    pk2=$!

    # wait for mini rules
    sleep 10

    local now1
    local sec
    local i

    for i in `seq $((t-15))`; do
        log "reconfig $i"
        config_ovs_nat
        sleep 1
        now1=`get_time`
        sec=`echo $now1 - $start1 + 1 | bc`
        if [ $sec -gt $t ]; then
            echo "elapsed $sec seconds"
            break
        fi
    done

    echo "stop"
    kill $pk1 $pk2 &>/dev/null
    wait &>/dev/null

    ovs-vsctl del-br ovs-br

    # wait for traces as merging & offloading is done in workqueue.
    sleep 3
}

run
trap - EXIT
cleanup
test_done
