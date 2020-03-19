#!/bin/bash
#
# Test ovs ct nat with tcp traffic, check miss
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module act_ct
echo 1 > /proc/sys/net/netfilter/nf_conntrack_tcp_be_liberal

ip="7.7.7.1"
ip_remote="8.8.8.8"
router_external_ip="8.8.8.1"
router_local_ip="7.7.7.2"

config_sriov 2
enable_switchdev_if_no_rep $REP
require_interfaces REP
unbind_vfs
bind_vfs
reset_tc $REP

VETH_REP=vrep0
VETH_VF=vvf0

function cleanup() {
    ovs-vsctl del-br br-ovs

    ip netns del ns0 2> /dev/null
    ip netns del ns1 2> /dev/null
    ip link del dev $VETH_REP &>/dev/null
    ip link del dev $VETH_VF &>/dev/null
}
trap cleanup EXIT

function swap_recirc_id() {
    echo $@ | grep -q -P "^recirc_id" && echo $@ && return

    recirc_id=`echo $@ | grep -o -P "recirc_id\(\dx?\d*\)"`
    rest=`echo $@ | sed 's/recirc_id(0x\?{:digit:]]*),//'`

    echo ${recirc_id},${rest}
}

function sorted_dump_flow_swap_recirc_id() {
    ovs-appctl dpctl/dump-flows $@ | while read x; do swap_recirc_id $x; done | sort
}

function ddumpct() {
    ports=`ovs-dpctl show | grep port | cut -d ":" -f 2 | grep -v internal`
    for p in $ports; do
        sorted_dump_flow_swap_recirc_id --names $@ | grep 'eth_type(0x0800)' | grep "in_port($p)"
        echo ""
    done
}

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

function config() {
    ip link add $VETH_REP type veth peer name $VETH_VF

    mac1=`cat /sys/class/net/$VF/address`
    remote_mac=`cat /sys/class/net/$VETH_VF/address`

    test "$mac1" || fail "no mac1"
    test "$remote_mac" || fail "no remote_mac"

    config_vf ns0 $VF $REP $ip
    config_vf ns1 $VETH_VF $VETH_REP $ip_remote

    router_mac="aa:bb:cc:dd:ee:ff"
    nat_range="1024-2048"
    ip -netns ns0 route add default via $router_local_ip dev $VF
    ip -netns ns0 neigh replace $router_local_ip dev $VF lladdr $router_mac
    ip -netns ns1 neigh replace $router_external_ip dev $VETH_VF lladdr $router_mac
}

t=10
pkts=500

function run() {
    title "Test OVS CT tcp nat - miss and continue in software"

    start_clean_openvswitch
    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs $VETH_REP

    ovs-ofctl del-flows br-ovs
    ovs-ofctl add-flow br-ovs "arp,actions=drop"
    ovs-ofctl add-flow br-ovs "table=0, ip,ct_state=-trk,in_port=$REP,dl_dst=$router_mac       actions=mod_dl_src=$router_mac,mod_dl_dst=$remote_mac,ct(zone=3, nat, table=1)"
    ovs-ofctl add-flow br-ovs "table=0, ip,ct_state=-trk,in_port=$VETH_REP,dl_dst=$router_mac  actions=mod_dl_src=$router_mac,mod_dl_dst=$mac1,ct(zone=3, nat, table=1)"

    ovs-ofctl add-flow br-ovs "table=1, ip,in_port=$REP,ct_state=+trk+new, actions=ct(commit, zone=3, nat(src=$router_external_ip:$nat_range)),output:$VETH_REP"
    ovs-ofctl add-flow br-ovs "table=1, ip,ct_state=+trk+est,in_port=$REP,       actions=output:$VETH_REP"
    ovs-ofctl add-flow br-ovs "table=1, ip,ct_state=+trk+est,in_port=$VETH_REP,  actions=output:$REP"

    ovs-ofctl dump-flows br-ovs --color

    echo "sleep before traffic"
    sleep 2

    echo "start tcpdump to sniff syn and ack packets"
    timeout $t tcpdump -qnnei $REP -c 2 'tcp' &
    pid=$!

    echo "run traffic for $t seconds"
    ip netns exec ns1 timeout $((t+1)) iperf -s -i 1 &
    sleep 0.5
    ip netns exec ns0 timeout $((t+1)) iperf -t $t -c $ip_remote &

    echo "wait for syn/ack tcpdump to capture handshake"
    wait $pid
    rc=$?
    if [[ $rc != 0 ]]; then
        err "fail to capture tcp handshake"
    fi

    pidof iperf &>/dev/null || err "iperf failed"

    echo "sleep to wait for offload"
    sleep 2

    echo "check if offloaded to flow table"
    res=`cat /proc/net/nf_conntrack | grep -i "zone=3" | grep "$ip_remote"`
    echo $res | grep --color=always -e "^" -i -e "offload"
    echo $res | grep -q -i offload || err "not offloaded to flow table"

    ddumpct

    echo "sniff $pkts software packets on $REP to /tmp/dump"
    rm /tmp/dump
    timeout $t tcpdump -qnnei $REP -c $pkts 'tcp' -w /tmp/dump &
    pid=$!

    sleep $t
    killall -9 iperf &>/dev/null
    wait $! 2>/dev/null

    # test sniff or timeout
    wait $pid
    rc=$?
    if [[ $rc -eq 0 ]]; then
        :
    else
        err "Failed to catch $pkts packets in software"
    fi

    ovs-vsctl del-br br-ovs
}

config
run

test_done
