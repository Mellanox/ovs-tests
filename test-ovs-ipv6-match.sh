#!/bin/bash
#
# Bug SW #998859: OVS not matching IPv6
#
#setup:
#       veth0 <-> veth1 <-> OVS <->  veth2 <-> veth3@ns0
#       VM1_IP                                    VM2_IP
#       veth4 <-> veth5 <-> OVS <->  veth6 <-> veth7@ns0
#       VM3_IP                                    VM4_IP

my_dir="$(dirname "$0")"
. $my_dir/common.sh


VM1_IP="2001:0db8:0:f101::1"
VM2_IP="2001:0db8:0:f101::2"
VM3_IP="2002:0db8:0:f101::1"
VM4_IP="2002:0db8:0:f101::2"


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
ip link add veth4 type veth peer name veth5
ip link add veth6 type veth peer name veth7

ip netns add ns0
ip link set veth3 netns ns0
ip netns exec ns0 ifconfig veth3 inet6 add $VM2_IP/64 up
ip link set veth7 netns ns0
ip netns exec ns0 ifconfig veth7 inet6 add $VM4_IP/64 up

ifconfig veth0 inet6 add $VM1_IP/64 up
ifconfig veth1 up
ifconfig veth2 up
ifconfig veth4 inet6 add $VM3_IP/64 up
ifconfig veth5 up
ifconfig veth6 up

echo "setup ovs"
systemctl restart openvswitch
sleep 2
del_all_bridges

ovs-vsctl add-br brv-1
ovs-vsctl add-port brv-1 veth1
ovs-vsctl add-port brv-1 veth2
ovs-vsctl add-port brv-1 veth5
ovs-vsctl add-port brv-1 veth6

function check_offloaded_rules() {
    local count=$1
    title " - check for $count offloaded rules"
    RES="ovs_dump_tc_flows | grep 0x86dd | grep \"ipv6(src=200\""
    eval $RES
    RES=`eval $RES | wc -l`
    if (( RES == $count )); then success; else err; fi
}

MATCH="ipv6,ipv6_src=2001::/16"
echo "add drop on match $MATCH"
ovs-ofctl add-flow brv-1 $MATCH,actions=drop

title "Test ping $VM1_IP -> $VM2_IP - expect to fail"
ping6 -q -c 2 -i 0.25 -w 2 $VM2_IP && err "ping expected to fail" || success

title "Verify we have 1 drop rule"
check_offloaded_rules 1

title "Test ping $VM3_IP -> $VM4_IP - expect to pass"
ping6 -q -c 10 -i 0.2 -w 4 $VM4_IP && success || err "ping failed"

title "Verify we have 3 rules, 1 drop rule, 2 redirect"
check_offloaded_rules 3

cleanup
test_done
