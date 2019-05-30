#!/bin/bash

my_dir="$(dirname "$0")"
. $my_dir/common.sh

NS1=n11
NS2=n12

BR11=br11
BR12=br12

BR21=br21
BR22=br22

# (REP)BR11(patch11) <--> (patch12)BR12(veth1) <--> (veth2)BR22(patch22) <--> (patch21)BR21(REP2)

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

function create_ip
{
    local link=$1 ip=$2 ns=$3

    ip netns exec $ns ip link set $link up
    ip netns exec $ns ip addr add $ip/24 dev $link
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

    create_ip $VF1 1.1.1.1 $NS1
    create_ip $VF2 1.1.1.2 $NS2

    ovs-vsctl add-br $BR11
    ovs-vsctl add-br $BR12

    ovs-vsctl add-br $BR21
    ovs-vsctl add-br $BR22

    ovs-vsctl				\
        -- add-port $BR11 patch11	\
        -- set interface patch11 type=patch options:peer=patch12  \
        -- add-port $BR12 patch12	\
        -- set interface patch12 type=patch options:peer=patch11  \

    ovs-vsctl				\
        -- add-port $BR21 patch21	\
        -- set interface patch21 type=patch options:peer=patch22  \
        -- add-port $BR22 patch22	\
        -- set interface patch22 type=patch options:peer=patch21  \

    ovs-vsctl add-port $BR11 $REP
    ovs-vsctl add-port $BR12 $VETH1

    ovs-vsctl add-port $BR21 $REP2
    ovs-vsctl add-port $BR22 $VETH2
}

function add_rules
{
    MAC1=$(ip netns exec $NS1 cat /sys/class/net/$VF1/address)
    MAC2=$(ip netns exec $NS2 cat /sys/class/net/$VF2/address)

    ovs-ofctl -O OpenFlow13 add-flow $BR12 in_port=patch12,actions=push_vlan:0x88a8,mod_vlan_vid=$SVID,output=$VETH1
    ovs-ofctl -O OpenFlow13 add-flow $BR12 dl_vlan=$SVID,actions=strip_vlan,patch12

    ovs-ofctl -O OpenFlow13 add-flow $BR11 in_port=patch11,arp,dl_vlan=$CVID,actions=strip_vlan,$REP
    ovs-ofctl -O OpenFlow13 add-flow $BR11 dl_vlan=$CVID,dl_dst=$MAC1,priority=10,actions=strip_vlan,$REP
    ovs-ofctl -O Openflow13 add-flow $BR11 in_port=$REP,ipv4,actions=push_vlan:0x8100,mod_vlan_vid=$CVID,output=patch11


    ovs-ofctl -O OpenFlow13 add-flow $BR22 in_port=patch22,actions=push_vlan:0x88a8,mod_vlan_vid=$SVID,output=$VETH2
    ovs-ofctl -O OpenFlow13 add-flow $BR22 dl_vlan=$SVID,actions=strip_vlan,patch22

    ovs-ofctl -O OpenFlow13 add-flow $BR21 in_port=patch21,arp,dl_vlan=$CVID,actions=strip_vlan,$REP2
    ovs-ofctl -O OpenFlow13 add-flow $BR21 dl_vlan=$CVID,dl_dst=$MAC2,priority=10,actions=strip_vlan,$REP2
    ovs-ofctl -O Openflow13 add-flow $BR21 in_port=$REP2,ipv4,actions=push_vlan:0x8100,mod_vlan_vid=$CVID,output=patch21
}

function do_test
{
    timeout 5 tcpdump -enn -i $VETH1 -w $tmpfile &
    ip netns exec $NS1 ping 1.1.1.2 -i 0.5 -c 10 && success || err
    sleep 1
    # verify tpid 802.1ad and vid 1000
    tcpdump -xxr $tmpfile  | grep 88a8 | grep 03e8 && success || err
}

cleanup
setup
add_rules
do_test
cleanup
test_done
