#!/bin/bash
#
# Test traffic offload for macvlan over bond interface
# Feature Request #3102442: Offloading support for Macvlan (passthru mode) over VF LAG bonding device
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_remote_server

IP="7.7.7.1"
REMOTE="7.7.7.2"

function config_ports() {
    config_sriov 2
    config_sriov 2 $NIC2
    enable_switchdev
    enable_switchdev $NIC2
    require_interfaces NIC NIC2 REP REP2
    unbind_vfs
    config_bonding $NIC $NIC2
    fail_if_err
    bind_vfs
}

function cleanup() {
    remove_ns
    ovs_clear_bridges
    cleanup_remote
    reset_tc $REP mymacvlan1 &> /dev/null
    ip link del dev mymacvlan1 &> /dev/null
    ip a flush dev $NIC
    unbind_vfs
    sleep 1
    clear_bonding
    enable_legacy $NIC2
    config_sriov 0 $NIC2
}

function remove_ns() {
    ip netns del ns0 &> /dev/null
}

function cleanup_remote() {
    clear_remote_bonding
    on_remote "ip a flush dev $REMOTE_NIC
               ip a flush dev $REMOTE_NIC2" &>/dev/null
}

function config_remote() {
    remote_disable_sriov
    config_remote_bonding
    on_remote "ip a add $REMOTE/24 dev bond0
               ip l set dev bond0 up"
}

trap cleanup EXIT

function config() {
    config_ports
    ip link add mymacvlan1 link bond0 type macvlan mode passthru
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
    on_remote timeout $((t+2)) iperf3 -s -D
    sleep 1
    ip netns exec ns0 timeout $((t+2)) iperf3 -t $t -c $REMOTE -P 3 &

    sleep 2
    pidof iperf3 &>/dev/null || err "iperf failed"

    ip netns exec ns0 timeout $((t-4)) tcpdump -qnnei $VF -c 30 'tcp' &
    pid1=$!

    echo "sniff packets on $REP"
    timeout $((t-4)) tcpdump -qnnei $REP -c 10 'tcp' &
    pid2=$!

    sleep $t
    killall -9 iperf3 &>/dev/null
    on_remote killall -9 iperf3 &>/dev/null
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
