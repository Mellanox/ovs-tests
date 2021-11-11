#!/bin/bash
#
# Test traffic offload for macvlan interface
# Feature Request #2121234: [Bytedance] CX5 ASAP2: Support macvlan interface in br-int for offload non-overlay traffic

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_remote_server

IP="7.7.7.1"
REMOTE="7.7.7.2"

config_sriov 2
enable_switchdev
unbind_vfs
bind_vfs
require_interfaces REP NIC VF

function cleanup() {
    remove_ns
    ovs_clear_bridges
    cleanup_remote
    reset_tc $REP mymacvlan1 &> /dev/null
    ip link del dev mymacvlan1 &> /dev/null
}

function remove_ns() {
    ip netns del ns0 &> /dev/null
}

function cleanup_remote() {
    on_remote ip a flush dev $REMOTE_NIC
}

function config_remote() {
    on_remote "ip a flush dev $REMOTE_NIC
               ip a add $REMOTE/24 dev $REMOTE_NIC
               ip l set dev $REMOTE_NIC up"
}

trap cleanup EXIT

function config() {
    ip link add mymacvlan1 link $NIC type macvlan mode passthru
    ip link set mymacvlan1 up
    reset_tc $REP mymacvlan1
    config_vf ns0 $VF $REP $IP
    config_ovs
    config_remote
}

function config_ovs() {
    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs mymacvlan1
    ovs-vsctl add-port br-ovs $REP
}

function run_traffic() {
    ip netns exec ns0 ping -q -c 1 -i 0.1 -w 2 $REMOTE
    if [ $? -ne 0 ]; then
        err "ping failed"
        return
    fi

    t=15
    echo "run traffic for $t seconds"
    on_remote timeout $((t+1)) iperf -s &
    sleep 1
    ip netns exec ns0 timeout $((t-1)) iperf -t $t -c $REMOTE -P 3 &

    sleep 2
    pidof iperf &>/dev/null || err "iperf failed"

    ip netns exec ns0 timeout $((t-4)) tcpdump -qnnei $VF -c 30 'tcp' &
    pid1=$!

    echo "sniff packets on $REP"
    timeout $((t-4)) tcpdump -qnnei $REP -c 10 'tcp' &
    pid2=$!

    sleep $t
    killall -9 iperf &>/dev/null
    wait $! 2>/dev/null

    title "Verify traffic on $VF"
    verify_have_traffic $pid1
    title "Verify traffic offload on $REP"
    verify_no_traffic $pid2

}

config
run_traffic
cleanup
trap - EXIT
test_done
