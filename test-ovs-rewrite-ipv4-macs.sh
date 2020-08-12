#!/bin/bash
#
# Bug SW #1506848: [upstream] Inconsistent lock state in act_pedit
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

not_relevant_for_cx4

VM1_IP="7.7.7.1"
VM2_IP="7.7.7.2"
FAKE_VM2_IP="7.7.7.3"
FAKE_VM1_IP="7.7.7.4"
FAKE_MAC="aa:bb:cc:dd:ee:ff"
FAKE_MAC_SRC="aa:12:34:56:78:ff"

# veth or hw
CASES=${CASES:-"hw"}

function cleanup() {
    echo "cleanup"
    start_clean_openvswitch
    ip netns del ns0 &> /dev/null

    for i in `seq 0 7`; do
        ip link del veth$i &> /dev/null
    done
}

function check_offloaded_rules() {
    local count=$1
    title " - check for $count offloaded rules"
    RES="ovs_dump_tc_flows | grep 0x0800 | grep -v drop"
    eval $RES
    RES=`eval $RES | wc -l`
    if (( RES == $count )); then success
    else
        ovs_dump_ovs_flows | grep 0x0800 | grep -v drop
        err
    fi
}

function kill_iperf_server() {
    if [ -n "$iperf_server_pid" ]; then
        kill -9 $iperf_server_pid &>/dev/null
        wait $iperf_server_pid &>/dev/null
    fi
}
trap kill_iperf_server EXIT

function test_traffic() {
    local dev=$1
    shift
    local iperf_extra=$@

    timeout -k1 4 iperf -c $FAKE_VM2_IP $iperf_extra -i 999 -t 1 || fail "Iperf failed"

    timeout 2 tcpdump -nnei $dev -c 3 'tcp' &
    tdpid=$!

    timeout -k1 4 iperf -c $FAKE_VM2_IP $iperf_extra -i 999 -t 3 && success || fail "Iperf failed"
    check_offloaded_rules 2

    title "Verify with tcpdump"
    wait $tdpid && err || success
}

function add_flow() {
    ovs-ofctl add-flow brv-1 $@
}

function test_case() {
    local cs=$1
    local VF=$VF
    local VF2=$VF2
    local REP=$REP
    local REP2=$REP2

    cleanup

    title "Test case $cs"
    start_check_syndrome

    if [[ "$cs" == "veth" ]]; then
        echo "setup veth and ns"
        ip link add veth0 type veth peer name veth1
        ip link add veth2 type veth peer name veth3

        VF=veth1
        VF2=veth3
        REP=veth0
        REP2=veth2
    elif [[ "$cs" == "hw" ]]; then
        enable_switchdev
        unbind_vfs
        bind_vfs
        require_interfaces VF VF2 REP REP2
    else
        fail "Unknown case: $cs"
    fi

    ifconfig $REP up
    ifconfig $VF $VM1_IP/24 up
    ifconfig $REP2 up
    ip netns add ns0
    ip link set $VF2 netns ns0
    ip netns exec ns0 ifconfig $VF2 $VM2_IP/24 up
    ip netns exec ns0 iperf -s -i 999 &
    iperf_server_pid=$!

    echo "setup ovs"
    ovs-vsctl add-br brv-1
    ovs-vsctl add-port brv-1 $REP -- set Interface $REP ofport_request=1
    ovs-vsctl add-port brv-1 $REP2 -- set Interface $REP2 ofport_request=2

    VF_MAC=`cat /sys/class/net/$VF/address`
    VF2_MAC=`ip netns exec ns0 cat /sys/class/net/$VF2/address`

    title "Test $VM1_IP -> fake $FAKE_VM2_IP (will be rewritten to $FAKE_VM1_IP -> $VM2_IP)"

    ovs-ofctl del-flows brv-1
    add_flow "ip,nw_src=$VM1_IP,nw_dst=$FAKE_VM2_IP,actions=mod_nw_src=$FAKE_VM1_IP,mod_nw_dst=$VM2_IP,normal"
    add_flow "ip,nw_src=$VM2_IP,nw_dst=$FAKE_VM1_IP,actions=mod_nw_src=$FAKE_VM2_IP,mod_nw_dst=$VM1_IP,normal"
    add_flow "arp,actions=normal"

    ip n replace $FAKE_VM2_IP dev $VF lladdr $VF2_MAC
    ip netns exec ns0 ip n replace $FAKE_VM1_IP dev $VF2 lladdr $VF_MAC

    test_traffic $REP

    stop_openvswitch
    service_ovs start
    ovs-ofctl del-flows brv-1

    title "Test [$VM1_IP @ $VF_MAC] -> [fake $FAKE_VM2_IP and fake mac $FAKE_MAC] (will be rewritten to [$FAKE_VM1_IP @ $FAKE_MAC_SRC] -> [$VM2_IP @ $VF2_MAC])"

    add_flow "ip,nw_src=$VM1_IP,nw_dst=$FAKE_VM2_IP,dl_src=$VF_MAC,dl_dst=$FAKE_MAC,actions=mod_nw_src=$FAKE_VM1_IP,mod_nw_dst=$VM2_IP,mod_dl_src=$FAKE_MAC_SRC,mod_dl_dst=$VF2_MAC,output:2"
    add_flow "ip,nw_src=$VM2_IP,nw_dst=$FAKE_VM1_IP,dl_src=$VF2_MAC,dl_dst=$FAKE_MAC_SRC,actions=mod_nw_src=$FAKE_VM2_IP,mod_nw_dst=$VM1_IP,mod_dl_src=$FAKE_MAC_SRC,mod_dl_dst=$VF_MAC,output:1"
    add_flow "arp,actions=normal"

    ip n replace $FAKE_VM2_IP dev $VF lladdr $FAKE_MAC
    ip netns exec ns0 ip n replace $FAKE_VM1_IP dev $VF2 lladdr $FAKE_MAC_SRC

    test_traffic $REP

    stop_openvswitch
    service_ovs start
    ovs-ofctl del-flows brv-1

    title "Test [$VM1_IP @ $VF_MAC] -> [fake $FAKE_VM2_IP and fake mac $FAKE_MAC]:fake port 5020 (will be rewritten to [$FAKE_VM1_IP @ $FAKE_MAC_SRC] -> [$VM2_IP @ $VF2_MAC]: port 5001)"

    add_flow "ip,nw_src=$VM1_IP,nw_dst=$FAKE_VM2_IP,dl_src=$VF_MAC,dl_dst=$FAKE_MAC,tcp,tcp_dst=5020,actions=mod_nw_src=$FAKE_VM1_IP,mod_nw_dst=$VM2_IP,mod_dl_src=$FAKE_MAC_SRC,mod_dl_dst=$VF2_MAC,mod_tp_dst=5001,output:2"
    add_flow "ip,nw_src=$VM2_IP,nw_dst=$FAKE_VM1_IP,dl_src=$VF2_MAC,dl_dst=$FAKE_MAC_SRC,tcp,tcp_src=5001actions=mod_nw_src=$FAKE_VM2_IP,mod_nw_dst=$VM1_IP,mod_dl_src=$FAKE_MAC_SRC,mod_dl_dst=$VF_MAC,mod_tp_src=5020,output:1"
    add_flow "arp,actions=normal"

    ip n replace $FAKE_VM2_IP dev $VF lladdr $FAKE_MAC
    ip netns exec ns0 ip n replace $FAKE_VM1_IP dev $VF2 lladdr $FAKE_MAC_SRC

    test_traffic $REP "-p 5020"

    check_syndrome
    kill_iperf_server
}

for cs in $CASES; do
    test_case $cs
done

cleanup
test_done
