#!/bin/bash
#
# In this test, we use veth to replace uplink representor.
# If using uplink representor in real use case, please run
# the following command to disable vlan strip:
#
# ethtool -K $PF rxvlan off
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

NS1=n11
NS2=n12

BR1=br1
BR2=br2

VETH1=veth1
VETH2=veth2

CVID=5
SVID=1000

tmpfile=/tmp/$$.pcap

function cleanup
{
    ip netns del $NS1 &> /dev/null
    ip netns del $NS2 &> /dev/null
    sleep 1
    ip link del $VETH1 &> /dev/null
    ip link del $VETH2 &> /dev/null

    ovs-vsctl remove Open_vSwitch . other_config vlan-limit
    start_clean_openvswitch
    rm -fr $tmpfile &>/dev/null
}

function create_ns_vlan
{
    local link=$1 vid=$2 ip=$3 vlan=vlan$2 ns=$4

    ip netns exec $ns ip link set $link up
    ip netns exec $ns ip link add link $link name $vlan type vlan id $vid
    ip netns exec $ns ip link set dev $vlan up
    ip netns exec $ns ip addr add $ip/24 dev $vlan
}

function setup
{
    config_sriov
    enable_switchdev_if_no_rep $REP
    bind_vfs

    ip link set $REP up
    ip link set $REP2 up

    ip netns add $NS1
    ip netns add $NS2

    ip link set $VF1 netns $NS1
    ip link set $VF2 netns $NS2
    sleep 1

    # by default vlan-limit is 1, pop action will not be offloaded
    ovs-vsctl set Open_vSwitch . other_config:vlan-limit=2

    ip link add $VETH1 type veth peer name $VETH2
    ip link set $VETH1 up
    ip link set $VETH2 up

    create_ns_vlan $VF1 $CVID 1.1.1.1 $NS1
    create_ns_vlan $VF2 $CVID 1.1.1.2 $NS2

    # by default, it is access port, vlan packet will be dropped
    tag="tag=$SVID vlan-mode=dot1q-tunnel"

    ovs-vsctl add-br $BR1
    ovs-vsctl add-br $BR2
    ovs-vsctl add-port $BR1 $VETH1
    ovs-vsctl add-port $BR1 $REP $tag

    ovs-vsctl add-port $BR2 $VETH2
    ovs-vsctl add-port $BR2 $REP2 $tag
}

function do_test
{
    title "Test OVS QinQ with qinq-ethtype=802.1ad"
    timeout 10 tcpdump -enn -i $VETH1 -w $tmpfile -c 5 &
    ip netns exec $NS1 ping 1.1.1.2 -c 5 && success || err
    # verify tpid 802.1ad (by default) and vid 1000
    tcpdump -xxr $tmpfile  | grep 88a8 | grep 03e8 && success || err

    title "Test OVS QinQ with qinq-ethtype=802.1q"
    # now test qing-ethtype=802.1q
    ovs-vsctl set Port $REP  other_config:qinq-ethtype=802.1q
    ovs-vsctl set Port $REP2 other_config:qinq-ethtype=802.1q

    timeout 10 tcpdump -enn -i $VETH1 -w $tmpfile -c 5 &
    ip netns exec $NS1 ping 1.1.1.2 -c 5 && success || err
    tcpdump -xxr $tmpfile  | grep 8100 | grep 03e8 && success || err
}

cleanup
setup
do_test
cleanup
test_done
