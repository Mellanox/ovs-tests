#!/bin/bash
#
# Test OVS with VF mirror
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

IP1="7.7.7.1"
IP2="7.7.7.2"

config_sriov 3
enable_switchdev
REP3=`get_rep 2`
unbind_vfs
bind_vfs
VF3=`get_vf 2`
require_interfaces REP REP2 REP3 VF VF2 VF3

function cleanup() {
    ip netns del ns0 2> /dev/null
    ip netns del ns1 2> /dev/null
    reset_tc $REP $REP2 $REP3
    config_sriov 2
    enable_switchdev
}
trap cleanup EXIT

function config_ovs() {
    echo "setup ovs"
    start_clean_openvswitch
    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs $REP2
    ovs-vsctl add-port br-ovs $REP3
    ovs-vsctl -- --id=@p1 get port $REP3 -- \
                --id=@m create mirror name=m1 select-all=true output-port=@p1 -- \
                set bridge br-ovs mirrors=@m || err "Failed to set mirror port"
    #ovs-vsctl list Bridge br-ovs | grep mirrors
    #ovs-vsctl clear bridge br-ovs mirrors
}

function run() {
    title "Test OVS with VF mirror"
    config_vf ns0 $VF $REP $IP1
    config_vf ns1 $VF2 $REP2 $IP2
    ip link set dev $REP3 up
    ip link set dev $VF3 up

    proto="icmp"
    config_ovs

    t=10

    echo "sniff packets on $VF3"
    timeout 2 tcpdump -qnnei $VF3 -c 20 $proto &
    pid3=$!
    sleep 0.5

    echo "run ping for $t seconds"
    ip netns exec ns0 ping $IP2 -q -i 0.02 -w $t &
    pk1=$!
    sleep 0.5

    echo "sniff packets on $REP"
    timeout $t tcpdump -qnnei $REP -c 1 $proto &
    pid2=$!

    wait $pk1 &>/dev/null

    echo "test traffic on $REP"
    verify_no_traffic $pid2
    echo "test mirror traffic on $VF3"
    verify_have_traffic $pid3

    ovs-vsctl del-br br-ovs
}


run
trap - EXIT
cleanup
test_done
