#!/bin/bash
#
# Bug SW #1015886: L3 IP matching is not working
#
#setup:
#       veth0 <-> veth1 <-> OVS <-> veth2 <-> veth3@ns0
#       VM1_IP                                   VM2_IP

my_dir="$(dirname "$0")"
. $my_dir/common.sh


VM1_IP="7.7.7.1"
VM2_IP="7.7.7.2"
VM2_IP2="7.7.7.22"

echo "deleting bridges"
ovs-vsctl list-br | xargs -r -l ovs-vsctl del-br

function cleanup() {
    echo "cleanup"
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
systemctl restart openvswitch
sleep 2
del_all_bridges

ovs-vsctl add-br brv-1
ovs-vsctl add-port brv-1 veth1
ovs-vsctl add-port brv-1 veth2


function check_offloaded_rules() {
    local count=$1
    title " - check for $count offloaded rules"
    RES="ovs-dpctl dump-flows type=offloaded | grep 0x0800 | grep \"ipv4(src=7.7.7\""
    eval $RES
    RES=`eval $RES | wc -l`
    if (( RES == $count )); then success; else err; fi
}

MATCH="ip,nw_src=$VM2_IP2"
echo "add drop on match $MATCH"
ovs-ofctl add-flow brv-1 $MATCH,actions=drop

title "Test ping $VM1_IP -> $VM2_IP - expect to pass"
ping -q -c 2 -w 2 $VM2_IP && success || err

title "Verify we have 2 rules"
check_offloaded_rules 2

title "Test ping $VM1_IP -> $VM2_IP2 - expect to fail"
ping -q -c 1 -w 2 $VM2_IP2 && err || success

title "Verify we have 3 rules"
check_offloaded_rules 3

del_all_bridges
cleanup
done2
