#!/bin/bash
#
# Test OVS CT TCP traffic
#
# IGNORE_FROM_TEST_ALL

my_dir="$(dirname "$0")"
. $my_dir/common.sh
testpmd="/labhome/roid/SWS/testpmd/testpmd"
pktgen="/labhome/roid/SWS/git2/network-testing/pktgen/pktgen_sample04_many_flows.sh"

require_module act_ct pktgen
echo 0 > /proc/sys/net/netfilter/nf_conntrack_tcp_be_liberal

IP1="7.7.7.1"
IP2="7.7.7.2"

config_sriov 2
enable_switchdev
require_interfaces REP REP2
unbind_vfs
bind_vfs
mac2=`cat /sys/class/net/$VF2/address`

pid_pktgen=""
function kill_pktgen() {
    test $pid_pktgen || return
    [ -e /proc/$pid_pktgen ] || return
    kill $pid_pktgen
    wait $pid_pktgen 2>/dev/null
    pid_pktgen=""
}

pid_testpmd=""
function kill_testpmd() {
    test $pid_testpmd || return
    [ -e /proc/$pid_testpmd ] || return
    killall -9 $pid_testpmd &>/dev/null
    killall $pid_testpmd &>/dev/null
}

function cleanup() {
    kill_testpmd
    kill_pktgen

    ip netns del ns0 2> /dev/null
    ip netns del ns1 2> /dev/null
    reset_tc $REP
    reset_tc $REP2
}
trap cleanup EXIT

function run_pktgen() {
    echo "run traffic"
    ip netns exec ns0 $pktgen -i $VF -t 10 -d $IP2 -m $mac2 &
    pid_pktgen=$!
    sleep 1
    if [ ! -e /proc/$pid_pktgen ]; then
        pid_pktgen=""
        err "pktgen failed"
        return 1
    fi
    return 0
}

function run_testpmd() {
    echo "run fwder"
    echo 2048 > /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages
    timeout --kill-after=10 60 ip netns exec ns1 tail -f /dev/null | $testpmd --vdev=eth_af_packet0,iface=$VF2 -- --forward-mode=macswap -a &
    pid_testpmd=$!
    sleep 1
    if [ ! -e /proc/$pid_testpmd ]; then
        pid_testpmd=""
        err "testpmd failed"
        return 1
    fi
    return 0
}

function config_ovs() {
    echo "setup ovs"
    start_clean_openvswitch

    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs $REP2

    ovs-ofctl add-flow br-ovs arp,actions=normal
    ovs-ofctl add-flow br-ovs "table=0, ip,ct_state=-trk,udp actions=ct(zone=12,table=1)"
    ovs-ofctl add-flow br-ovs "table=0, ip,ct_state=-trk,tcp actions=ct(zone=12,table=1)"
    ovs-ofctl add-flow br-ovs "table=1, ip,ct_state=+trk+new actions=ct(zone=12,commit),normal"
    ovs-ofctl add-flow br-ovs "table=1, ip,ct_state=+trk+est,ct_zone=12 actions=normal"

    ovs-ofctl dump-flows br-ovs --color
}

function run() {
    title "Test OVS CT TCP"

    config_vf ns0 $VF $REP $IP1
    config_vf ns1 $VF2 $REP2 $IP2
    config_ovs

    echo "prepare for offload, 2048 hugepages and nf_flow_offload_timeout=600, nf_conntrack_max=524288"
    #echo 600 > /sys/module/nf_flow_table/parameters/nf_flow_offload_timeout
    sysctl -w 'net.netfilter.nf_conntrack_max=524288'

    echo "add zone 12 rule for priming offload callbacks"
    tc_filter add dev $REP prio 1337 proto ip chain 1337 ingress flower \
        skip_sw ct_state -trk action ct zone 12 pipe \
        action mirred egress redirect dev $REP2

    echo "sleep 3 sec, fg now"
    sleep 3

#    run_pktgen || return
#    run_testpmd || return
#    sleep 65

    echo "count"
#    cat /proc/net/nf_conntrack | grep --color=auto -i offload

    kill_pktgen
    kill_testpmd
    ovs-vsctl del-br br-ovs
    conntrack -F
}


cleanup
run
cleanup
test_done
