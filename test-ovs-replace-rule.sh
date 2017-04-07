#!/bin/bash
#
# Bug SW #984397: OVS reports failed to put[modify] (No such file or directory)
#

NIC=${1:-ens5f0}

my_dir="$(dirname "$0")"
. $my_dir/common.sh


LOCAL_IP=99.99.99.5
REMOTE_IP=99.99.99.6
CLEAN="sed -e 's/used:.*, act/used:used, act/;s/eth(src=[a-z0-9:]*,dst=[a-z0-9:]*)/eth(macs)/;s/recirc_id(0),//;s/,ipv4(.*)//' | sort"

function cleanup() {
    echo "cleanup"
    start_clean_openvswitch
    ip link del dev veth2 &> /dev/null
    ip link del dev veth0 &> /dev/null
    ip netns del red &> /dev/null
    ip netns del blue &> /dev/null
}
cleanup

echo "setup netns"
ip netns add red
ip netns add blue
ip link add veth2 type veth peer name veth3
ip link add veth0 type veth peer name veth1
ip link set veth1 netns red
ip netns exec red ip addr add $LOCAL_IP/24 dev veth1
ip netns exec red ip link set veth1 up
ip link set veth3 netns blue
ip netns exec blue ip addr add $REMOTE_IP/24 dev veth3
ip netns exec blue ip link set veth3 up
ifconfig veth2 up
ifconfig veth0 up

echo "clean ovs"
del_all_bridges
systemctl restart openvswitch
sleep 2
del_all_bridges

echo "prep ovs"
ovs-vsctl add-br br3
ovs-vsctl add-port br3 veth0
ovs-vsctl add-port br3 veth2

# generate rule
ip netns exec red ping $REMOTE_IP -i 0.25 -c 8 

function check_offloaded_rules() {
    title " - check for $1 offloaded rules"
    RES="ovs-dpctl dump-flows type=offloaded | grep 0x0800 | $CLEAN"
    eval $RES
    RES=`eval $RES | wc -l`
    if (( RES == $1 )); then success; else err; fi
}

function check_ovs_rules() {
    title " - check for $1 ovs dp rules"
    RES="ovs-dpctl dump-flows type=ovs | grep 0x0800 | $CLEAN"
    eval $RES
    RES=`eval $RES | wc -l`
    if (( RES == $1 )); then success; else err; fi
}



check_offloaded_rules 2
check_ovs_rules 0

title "change ofctl normal rule to all"
ovs-ofctl del-flows br3
ovs-ofctl add-flow br3 dl_type=0x0800,actions=all
sleep 1
check_offloaded_rules 0
check_ovs_rules 2

title "change ofctl all rule to normal"
ovs-ofctl del-flows br3
ovs-ofctl add-flow br3 dl_type=0x0800,actions=normal
sleep 1
check_offloaded_rules 2
check_ovs_rules 0

title "change ofctl normal rule to drop"
ovs-ofctl del-flows br3
ovs-ofctl add-flow br3 dl_type=0x0800,actions=drop
sleep 1
check_offloaded_rules 2
check_ovs_rules 0

cleanup
test_done
