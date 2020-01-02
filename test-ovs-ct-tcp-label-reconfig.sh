#!/bin/bash
#
# Test OVS CT TCP with label and reconfig flows during traffic
#
# With CT multi-table we currently only support labels of 32 bits so we might
# see an error in dmesg like
# [95869.250616] mlx5_core 0000:82:00.0 ens1f0: Failed to offload ct entry, err: -95
#
# the purpose of the test is not catching this but the kasan bug reproduce later
# [95966.187839] BUG: KASAN: use-after-free in rht_deferred_worker+0x14db/0x1600

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module act_ct
echo 1 > /proc/sys/net/netfilter/nf_conntrack_tcp_be_liberal

IP1="7.7.7.1"
IP2="7.7.7.2"

config_sriov 2
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

function reconfig_flows() {
    ovs-ofctl del-flows br-ovs
    ovs-ofctl add-flow br-ovs arp,actions=normal
    ovs-ofctl add-flow br-ovs "table=0, ip,ct_state=-trk actions=ct(table=1)"
    ovs-ofctl add-flow br-ovs "table=1, ip,ct_state=+trk+new actions=ct(commit,exec(set_field:0xffffffffffffffffffff->ct_label)),normal"
    ovs-ofctl add-flow br-ovs "table=1, ip,ct_state=+trk+est actions=normal"
}

function run() {
    title "Test OVS CT TCP"
    config_vf ns0 $VF $REP $IP1
    config_vf ns1 $VF2 $REP2 $IP2

    echo "setup ovs"
    start_clean_openvswitch
    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs $REP2

    reconfig_flows
    ovs-ofctl dump-flows br-ovs --color

    t=30
    echo "run traffic for $t seconds"
    ip netns exec ns1 timeout $((t+1)) iperf -s &
    sleep 0.5
    ip netns exec ns0 timeout $((t+1)) iperf -t $t -c $IP2 -P 3 &

    sleep 2
    pidof iperf &>/dev/null || err "iperf failed"

    for i in `seq 10`; do
        title "reconfig $i"
        reconfig_flows
        sleep 1
    done

    killall -9 iperf &>/dev/null
    wait $! 2>/dev/null

    ovs-vsctl del-br br-ovs
}


run
test_done
