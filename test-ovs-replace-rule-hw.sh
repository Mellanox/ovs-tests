#!/bin/bash
#
# Bug SW #984397: OVS reports failed to put[modify] (No such file or directory)
#
# There is a workaround in OVS where we delete existing rule before adding new
# one to avoid doing replace. This works around issue #988519.
#  #988519: Trying to replace a flower rule cause a syndrome and rule to be deleted
#

NIC=${1:-ens5f0}
VF1=${2:-ens5f2}
VF2=${3:-ens5f3}

my_dir="$(dirname "$0")"
. $my_dir/common.sh

enable_switchdev
bind_vfs

LOCAL_IP=99.99.99.5
REMOTE_IP=99.99.99.6
CLEAN="sed -e 's/used:.*, act/used:used, act/;s/eth(src=[a-z0-9:]*,dst=[a-z0-9:]*)/eth(macs)/;s/recirc_id(0),//;s/,ipv4(.*)//' | sort"

port1=$VF1
port2=$REP
port3=$VF2
port4=$REP2

if [ -z "$port2" ]; then
    fail "Missing rep $port2"
    exit 1
fi
if [ -z "$port4" ]; then
    fail "Missing rep $port4"
    exit 1
fi

function cleanup() {
    echo "cleanup"
    start_clean_openvswitch
    ip netns del red &> /dev/null
    ip netns del blue &> /dev/null
}
cleanup

err=0
for i in port1 port2 port3 port4; do
    if [ ! -e /sys/class/net/${!i} ]; then
        err "Cannot find interface ${!i}"
        err=1
    fi
done

if [ "$err" = 1 ]; then
    test_done
fi

echo "setup netns"
ip netns add red
ip netns add blue
ip link set $port1 netns red
ip link set $port3 netns blue
ip netns exec red ifconfig $port1 $LOCAL_IP/24 up
ip netns exec blue ifconfig $port3 $REMOTE_IP/24 up
ifconfig $port2 up
ifconfig $port4 up

echo "clean ovs"
start_clean_openvswitch

echo "prep ovs"
ovs-vsctl add-br br3
ovs-vsctl add-port br3 $port2
ovs-vsctl add-port br3 $port4

# generate rule
ip netns exec red ping -i 0.25 -c 8 $REMOTE_IP

function check_offloaded_rules() {
    title " - check for $1 offloaded rules"
    RES="ovs_dump_tc_flows | grep 0x0800 | $CLEAN"
    eval $RES
    RES=`eval $RES | wc -l`
    if (( RES == $1 )); then success; else err; fi
}

function check_double_action_rules() {
    title " - check for $1 double action rules"
    RES="ovs_dump_flows | grep 0x0800 | grep actions:.,. | $CLEAN"
    eval $RES
    RES=`eval $RES | wc -l`
    if (( RES == $1 )); then success; else err; fi
}


check_offloaded_rules 2
check_double_action_rules 0

title "change ofctl normal rule to all"
start_check_syndrome
ovs-ofctl del-flows br3
ovs-ofctl add-flow br3 dl_type=0x0800,actions=all
sleep 1
check_double_action_rules 2
check_syndrome || err

title "change ofctl all rule to normal"
start_check_syndrome
ovs-ofctl del-flows br3
ovs-ofctl add-flow br3 dl_type=0x0800,actions=normal
sleep 1
check_offloaded_rules 2
check_double_action_rules 0
check_syndrome || err

title "change ofctl normal rule to drop"
start_check_syndrome
ovs-ofctl del-flows br3
ovs-ofctl add-flow br3 dl_type=0x0800,actions=drop
sleep 1
check_offloaded_rules 2
check_double_action_rules 0
check_syndrome || err

cleanup
test_done
