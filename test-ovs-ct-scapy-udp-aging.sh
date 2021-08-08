#!/bin/bash
#
# Test OVS CT aging
# Test conntrack aging before OVS aging
# Expected result not get list_del corruption.
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh
pktgen=$my_dir/scapy-traffic-tester.py

require_module act_ct

IP1="7.7.7.1"
IP2="7.7.7.2"

function test_ct_aging() {
    if ! sysctl -a |grep net.netfilter.nf_flowtable_udp_timeout >/dev/null 2>&1 ; then
        fail "Cannot set conntrack offload aging - missing net.netfilter.nf_flowtable_udp_timeout"
    fi
}

function set_ct_aging() {
    local timeout=$1
    sysctl -w net.netfilter.nf_flowtable_udp_timeout=$timeout || err "Failed setting udp timeout"
}


test_ct_aging
enable_switchdev
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
    set_ct_aging 30 &>/dev/null
}
trap cleanup EXIT

function config_ovs() {
    local proto=$1

    echo "setup ovs"
    conntrack -F
    start_clean_openvswitch
    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs $REP2

    ovs-ofctl add-flow br-ovs in_port=$REP,dl_type=0x0806,actions=output:$REP2
    ovs-ofctl add-flow br-ovs in_port=$REP2,dl_type=0x0806,actions=output:$REP

    ovs-ofctl add-flow br-ovs "table=0, $proto,ct_state=-trk actions=ct(table=1,nat)"
    ovs-ofctl add-flow br-ovs "table=1, $proto,ct_state=+trk+new actions=ct(commit),normal"
    ovs-ofctl add-flow br-ovs "table=1, $proto,ct_state=+trk+est actions=normal"

    ovs-ofctl dump-flows br-ovs --color
}

function run() {
    title "Test OVS CT aging"
    config_vf ns0 $VF $REP $IP1
    config_vf ns1 $VF2 $REP2 $IP2

    proto="udp"
    config_ovs $proto
    set_ct_aging 10
    fail_if_err

    t=5
    echo "run traffic for $t seconds"
    ip netns exec ns1 $pktgen -l -i $VF2 --src-ip $IP1 --time $((t+1)) &
    pk1=$!
    sleep 1
    ip netns exec ns0 $pktgen -i $VF1 --src-ip $IP1 --dst-ip $IP2 --time $t &
    pk2=$!

    sleep $t
    kill $pk1 &>/dev/null
    wait $pk1 $pk2 2>/dev/null

    if ! cat /proc/net/nf_conntrack |grep 7.7.7 |grep HW >/dev/null 2>&1 ; then
        err "UDP connection is not offloaded"
        return
    fi

    echo waitng for offload aging
    sleep 12

    if ! cat /proc/net/nf_conntrack |grep 7.7.7 |grep ASSURED >/dev/null 2>&1 ; then
        err "UDP connection is not in software"
        return
    fi

    conntrack -F
}


run
echo clean
ovs-vsctl del-br br-ovs

test_done
