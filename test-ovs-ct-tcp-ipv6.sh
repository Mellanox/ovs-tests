#!/bin/bash
#
# Test ovs ct with tcp traffic - ipv6
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module act_ct
echo 1 > /proc/sys/net/netfilter/nf_conntrack_tcp_be_liberal

ip1="2001:0db8:0:f101::1"
ip2="2001:0db8:0:f101::2"

config_sriov 2
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
        sorted_dump_flow_swap_recirc_id --names $@ | grep -i 'eth_type(0x86dd)' | grep "in_port($p)"
        echo ""
    done
}

function config() {
    config_vf ns0 $VF $REP $ip1
    config_vf ns1 $VF2 $REP2 $ip2

    ip -6 -netns ns0 neigh replace $ip2 dev $VF lladdr $mac2
    ip -6 -netns ns1 neigh replace $ip1 dev $VF2 lladdr $mac1
}

function run() {
    echo "setup ovs with ct"

    start_clean_openvswitch
    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs $REP2

    ovs-ofctl del-flows br-ovs
    ovs-ofctl add-flow br-ovs "arp,                                                        actions=drop"
    ovs-ofctl add-flow br-ovs "table=0, ipv6,ct_state=-trk,                                actions=ct(table=1)"
    ovs-ofctl add-flow br-ovs "table=1, ipv6,in_port=$REP,ct_state=+trk+new,               actions=ct(commit),output:$REP2"
    ovs-ofctl add-flow br-ovs "table=1, ipv6,ct_state=+trk+est,                            action=normal"

    ovs-ofctl dump-flows br-ovs --color

    echo "sleeping before starting traffic"
    sleep 1

    echo "run traffic"
    t=12
    echo "run traffic for $t seconds"
    ip netns exec ns1 timeout $((t+1)) iperf -s --ipv6_domain &
    sleep 0.5
    ip netns exec ns0 timeout $((t+1)) iperf --ipv6_domain -c $ip2 -t $t -P 3 &

    sleep 2
    pidof iperf &>/dev/null || err "iperf failed"

    echo "sniff packets on $REP"
    timeout $t tcpdump -qnnei $REP -c 10 'tcp' &
    pid=$!


    ddumpct
    ddumpct --names | grep -q -P "ct(.*commit.*)" || err "Expected ct commit action"

    sleep $t
    killall -9 iperf &>/dev/null
    wait $! 2>/dev/null

    # test sniff timedout
    wait $pid
    rc=$?
    if [[ $rc -eq 124 ]]; then
        :
    elif [[ $rc -eq 0 ]]; then
        err "Didn't expect to see packets"
    else
        err "Tcpdump failed"
    fi

    ovs-vsctl del-br br-ovs
}

title "Test OVS CT tcp - ipv6"

config
run

test_done
