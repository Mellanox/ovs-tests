#!/bin/bash
#
# This test helps reproduce issue where encap rules not offloaded because
# OVS added tos rewrite which the hw doesn't support.
#
# Bug SW #1332238: OVS adds TOS in the case of re-write any L3 field
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


VM1_IP="7.7.7.1"
VM2_IP="7.7.7.2"
FAKE_VM2_IP="7.7.7.3"

local_tun="2.2.2.2"
remote_tun="2.2.2.3"


function cleanup() {
    echo "cleanup"
    start_clean_openvswitch
    ip l del dev vxlan_sys_4789 &>/dev/null
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
ip netns exec ns0 ifconfig veth3 $remote_tun/24 up

ip netns exec ns0 ip link add name vxlan42 type vxlan id 42 dev veth3 remote $local_tun dstport 4789
ip netns exec ns0 ifconfig vxlan42 $VM2_IP/24 up

echo "setup ovs"
ovs-vsctl add-br brv-1
ovs-vsctl add-port brv-1 veth1
ovs-vsctl add-port brv-1 vxlan0 -- set interface vxlan0 type=vxlan options:local_ip=$local_tun options:remote_ip=$remote_tun options:key=42 options:dst_port=4789

ifconfig veth2 $local_tun/24 up

function check_offloaded_rules() {
    local count=$1
    title " - check for $count offloaded rules"
    RES="ovs_dpctl_dump_flows | grep 0x0800 | grep -v drop"
    eval $RES
    RES=`eval $RES | wc -l`
    if (( RES == $count )); then success
    else
         ovs-appctl dpctl/dump-flows type=ovs | grep 0x0800 | grep -v drop
         err
    fi
}

title "Test normal ping $VM1_IP -> $VM2_IP and learn mac address"
ping -q -c 10 -i 0.2 -w 4 $VM2_IP && success || err

check_offloaded_rules 2

ip n | grep $VM2_IP | sed "s/$VM2_IP/$FAKE_VM2_IP/" | cut -d " " -f 1-5 | xargs ip n replace

ovs-ofctl del-flows brv-1
ovs-ofctl add-flow brv-1 "ip,nw_dst=$FAKE_VM2_IP,actions=mod_nw_dst=$VM2_IP,normal"
ovs-ofctl add-flow brv-1 "ip,nw_dst=$VM1_IP,actions=mod_nw_src=$FAKE_VM2_IP,normal"
ovs-ofctl add-flow brv-1 "arp,actions=normal"
ovs-dpctl del-flows

title "Test ping $VM1_IP -> fake $FAKE_VM2_IP (will be rewritten to $VM2_IP)"
ping -q -c 10 -i 0.2 -w 4 $FAKE_VM2_IP && success || err

check_offloaded_rules 2

cleanup
test_done
