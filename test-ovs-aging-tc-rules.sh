#!/bin/bash
#
# Verify ovs aging mechanism works for rules in tc.
# When ovs adds rule to tc it saves the replied handle with ufid mapping
# and dumping/deleting the rule according to that mapping.
#
# Bug SW #1647555: [UCloud] rules are not aging after a long time
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


VM1_IP="7.7.7.1"
VM2_IP="7.7.7.2"
VM2_IP2="7.7.7.22"


function cleanup() {
    echo "cleanup"
    start_clean_openvswitch
    ip netns del ns0 &> /dev/null

    for i in `seq 0 7`; do
        ip link del veth$i &> /dev/null
    done
}

cleanup

echo "setup veth and ns"
ip link add veth0 type veth peer name veth1
ip link add veth2 type veth peer name veth3

ifconfig veth0 $VM1_IP/24 up
ifconfig veth1 up
ifconfig veth2 up

ip netns add ns0
ip link set veth3 netns ns0
ip netns exec ns0 ifconfig veth3 $VM2_IP/24 up
ip netns exec ns0 ip a add $VM2_IP2/24 dev veth3

echo "setup ovs"
ovs-vsctl add-br brv-1
ovs-vsctl add-port brv-1 veth1
ovs-vsctl add-port brv-1 veth2


function check_offloaded_rules() {
    local count=$1
    title " - check for $count offloaded rules"
    RES="ovs_dump_tc_flows | grep 0x0800 | grep \"ipv4(src=7.7.7\""
    eval $RES
    RES=`eval $RES | wc -l`
    if (( RES == $count )); then success; else err; fi
}

MATCH="ip,nw_src=$VM2_IP2"
echo "add drop on match $MATCH"
ovs-ofctl add-flow brv-1 $MATCH,actions=drop

title "Test ping $VM1_IP -> $VM2_IP - expect to pass"
ping -q -c 2 -i 0.2 -w 2 $VM2_IP && success || err "ping failed"

title "Verify we have 2 rules"
check_offloaded_rules 2

title "Test aging mechanism"
ovs-vsctl set Open_vSwitch . other_config:max-idle=1 || err "set max-idle failed"
ovs-vsctl remove Open_vSwitch . other_config max-idle || err "remove max-idle failed"
check_offloaded_rules 0

cleanup
test_done
