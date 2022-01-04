#!/bin/bash
#
# Test nat miss from tc to OVS for connection in NEW state
#
# We use datahpath hash action and match (groups in openflow) so the ct(commit,..) rule won't be offloaded to tc.
# We then run a single sided UDP connection which should always be in NEW state as there is not reply.
# The first rule doing ct(nat) action should be offloaded to tc, and not restore nat for packets in NEW state.
# The packets then miss from tc to OVS datapath, which should execute nat in the ct(commit, nat(src=...)) action.
#
# Bug SW #2890028: DNS lookup failures when run two times in a row
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module act_ct

ip1="1.1.1.1"
ip2="1.1.2.1"

function add_netns() {
    local ns=$1
    local ip=$2
    local peer=${ns}_peer
    local veth=${ns}_veth

    echo "Create namespace $ns, veths: hv $veth <-> ns $peer ($ip)"
    ip netns add $ns
    ip link del $veth &>/dev/null
    ip link add $veth type veth peer name $peer
    ip link set $veth up
    ip link set $peer netns $ns
    ip netns exec $ns ifconfig $peer $ip/16 mtu 1400 up
    ovs-vsctl add-port ovs-br $veth
}

function setup() {
    start_clean_openvswitch
    ovs-vsctl set Open_vSwitch . other_config:max-idle=100000
    ovs-vsctl add-br ovs-br

    add_netns ns1 1.1.1.1
    add_netns ns2 1.1.2.1
}

function cleanup() {
    killall -9 nc &> /dev/null
    ip -all netns del
    ovs_clear_bridges
    ovs-vsctl remove Open_vSwitch . other_config max-idle
}
trap cleanup EXIT

function run_scpy_udp() {
    sport=$((RANDOM%60000 + 1000))
    dport=$((RANDOM%60000 + 1000))

    ip netns exec ns1 ip link set lo up
    ip netns exec ns2 ip link set lo up

     echo "Connection $ip1:$sport --> $ip2:$dport - start"
     for i in `seq 5`; do
         ip netns exec ns1 python -c "from scapy.all import *; send(IP(src=\"$ip1\",dst=\"$ip2\")/UDP(sport=$sport,dport=$dport)/\"AAAAA\")"
     done
}

function test1() {
    title "Add open flow rules"

    #groups
    ovs-ofctl -O OpenFlow12 add-group ovs-br 'group_id=2,type=select,bucket=ct(table=4,zone=5,nat(src=1.1.1.128),commit)'

    #rules
    ovs-ofctl del-flows ovs-br

    ovs-ofctl add-flow ovs-br "table=0, arp, action=normal"
    ovs-ofctl add-flow ovs-br "table=0, ip, nw_src=1.1.1.1 actions=ct(zone=5,table=1,nat)"

    ovs-ofctl add-flow ovs-br "table=1, in_port=1, actions=group:2"

    ovs-ofctl add-flow ovs-br "table=4, ip, nw_src=1.1.1.128 actions=2" #good flow
    ovs-ofctl add-flow ovs-br "table=4, ip, nw_src=1.1.1.1 actions=drop" #bad flow

    if false; then
        #return for debug
        :

        #ovs-ofctl add-flow ovs-br "table=0, ip, nw_src=1.1.2.1 actions=ct(zone=5,table=1,nat)"
        #ovs-ofctl -O OpenFlow12 add-group ovs-br 'group_id=1,type=select,bucket=ct(table=3,zone=5,nat,commit)'
        #ovs-ofctl add-flow ovs-br "table=1, in_port=2, actions=group:1"
        #ovs-ofctl add-flow ovs-br "table=3, ip, nw_src=1.1.2.1 actions=output:1"
    fi

    title "Groups"
    ovs-ofctl dump-groups ovs-br

    title "Open flow"
    ovs-ofctl dump-flows ovs-br

    log "Flush conntrack"
    conntrack -F

    title "Run traffic"
    run_scpy_udp

    res=`ovs-appctl dpctl/dump-flows --names | grep -i "in_port(ns1_veth)" | grep -i "0x0800"`
    echo "$res"

    title "verify output rule exists"
    echo "$res" |  grep -i "src=1.1.1.128" | grep -q "ns2_veth" || err "Failed finding output rule"

    title "verify source nat was executed"
    echo "$res" |  grep -i "src=1.1.1.1" | grep -q "drop" && err "Found old ip in next recirc, indicating nat not being executed"
}


cleanup
setup
test1
test_done
