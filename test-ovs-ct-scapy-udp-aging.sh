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
    [ -e /sys/module/mlx5_core/parameters/offloaded_ct_timeout ] && return
    [ -e /sys/module/act_ct/parameters/offload_timeout ] && return
    fail "Cannot set conntrack offload aging"
}

function set_ct_aging() {
    local val=$1
    local dest
    if [ -e /sys/module/mlx5_core/parameters/offloaded_ct_timeout ]; then
        dest=/sys/module/mlx5_core/parameters/offloaded_ct_timeout
    elif [ -e /sys/module/act_ct/parameters/offload_timeout ]; then
        dest=/sys/module/act_ct/parameters/offload_timeout
    fi
    echo $val > $dest || err "Failed to set conntrack offload aging"
}


enable_switchdev
require_interfaces REP REP2
test_ct_aging
unbind_vfs
bind_vfs
reset_tc $REP
reset_tc $REP2


function cleanup() {
    ip netns del ns0 2> /dev/null
    ip netns del ns1 2> /dev/null
    reset_tc $REP
    reset_tc $REP2
    set_ct_aging 30
}
trap cleanup EXIT

function config_ovs() {
    local proto=$1

    echo "setup ovs"
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
    set_ct_aging 2
    fail_if_err

    t=10
    echo "run traffic for $t seconds"
    ip netns exec ns1 $pktgen -l -i $VF2 --src-ip $IP1 --time $((t+1)) &
    pk1=$!
    sleep 1
    ip netns exec ns0 $pktgen -i $VF1 --src-ip $IP1 --dst-ip $IP2 --time $t &
    pk2=$!

    sleep $t
    kill $pk1 &>/dev/null
    wait $pk1 $pk2 2>/dev/null

    echo wait
    sleep 10

    echo clean
    ovs-vsctl del-br br-ovs

    # wait for traces as merging & offloading is done in workqueue.
    sleep 3
}


run
test_done
