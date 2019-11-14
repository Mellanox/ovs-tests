#!/bin/bash
#
# Test ovs ct nat and mark (for mac restoration) with tcp traffic
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
require_interfaces REP REP2
unbind_vfs
bind_vfs
reset_tc $REP
reset_tc $REP2

mac1=`cat /sys/class/net/$VF/address`
remote_mac=`cat /sys/class/net/$VF2/address`

test "$mac1" || fail "no mac1"
test "$remote_mac" || fail "no remote_mac"

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
    config_vf ns0 $VF $REP $ip
    config_vf ns1 $VF2 $REP2 $ip_remote

    router_mac="aa:bb:cc:dd:ee:ff"
    nat_range="1024-2048"
    ip -netns ns0 route add default via $router_local_ip dev $VF
    ip -netns ns0 neigh replace $router_local_ip dev $VF lladdr $router_mac
    ip -netns ns1 neigh replace $router_external_ip dev $VF2 lladdr $router_mac
}

function run() {
    title "- setup ovs with ct hops: $hops"

    start_clean_openvswitch
    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs $REP2

    ovs-ofctl del-flows br-ovs
    ovs-ofctl add-flow br-ovs "arp,actions=drop"
    if [[ "$hops" == 1 ]]; then
        ovs-ofctl add-flow br-ovs "table=0, ip,dl_dst=$router_mac,ct_state=-trk, actions=ct(nat, table=1)"
    else
        ovs-ofctl add-flow br-ovs "table=0, ip,dl_dst=$router_mac,ct_state=-trk, actions=ct(table=1)"
    fi

    ovs-ofctl add-flow br-ovs "table=1, ip,in_port=$REP,ip_dst=$ip_remote,ct_state=+trk+new, actions=ct(commit,nat(src=$router_external_ip:$nat_range),exec(set_field:1->ct_mark)),mod_dl_src=$router_mac,mod_dl_dst=$remote_mac,output:$REP2"

    if [[ "$hops" == 1 ]]; then
        ovs-ofctl add-flow br-ovs "table=1, ip,ct_state=+trk+est,          action=goto_table=2"
    else
        ovs-ofctl add-flow br-ovs "table=1, ip,ct_state=+trk+est,          action=ct(nat, table=2)"
    fi

    ovs-ofctl add-flow br-ovs "table=2, ip,in_port=$REP,ip_dst=$ip_remote, actions=mod_dl_src=$router_mac,mod_dl_dst=$remote_mac,output:$REP2"
    ovs-ofctl add-flow br-ovs "table=2, ip,in_port=$REP2,ct_mark=1,        actions=mod_dl_src=$router_mac,mod_dl_dst=$mac1,output:$REP"

    #TODO test ct(nat),fwd

    ovs-ofctl dump-flows br-ovs --color

    echo "sleep before traffic"
    sleep 2

    echo "run traffic"
    t=12
    echo "run traffic for $t seconds"
    ip netns exec ns1 timeout $((t+1)) iperf -s &
    sleep 0.5
    ip netns exec ns0 timeout $((t+1)) iperf -t $t -c $ip_remote -P 3 &

    sleep 2
    pidof iperf &>/dev/null || err "iperf failed"

    echo "sniff packets on $REP"
    timeout $t tcpdump -qnnei $REP -c 10 'tcp' &
    pid=$!


    ddumpct
    ovs_dump_tc_flows --names | grep -q -P "ct(.*commit.*)" || err "Expected ct commit action"

    sleep $t
    killall iperf &>/dev/null
    killall iperf &>/dev/null
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

config

title "Test OVS CT tcp nat and mark"
hops=1
run
hops=2
run

test_done
