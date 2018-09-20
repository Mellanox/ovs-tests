#!/bin/bash

my_dir="$(dirname "$0")"
. $my_dir/common.sh


VM1_IP="7.7.7.1"
VM2_IP="7.7.7.2"

local_tun="2.2.2.2"
remote_tun="2.2.2.3"


function cleanup() {
    echo "cleanup"
    ip netns del ns0 &>/dev/null
    ifconfig $NIC 0
    start_clean_openvswitch
}

enable_switchdev_if_no_rep $REP
unbind_vfs
set_eswitch_inline_mode_transport
bind_vfs
require_interfaces VF REP
cleanup

echo "setup ovs"
ifconfig $REP up
ifconfig $NIC $local_tun/24 up
ip n replace ${remote_tun} dev $NIC lladdr 11:22:33:44:55:66

ip netns add ns0
ip link set $VF netns ns0
ip netns exec ns0 ifconfig $VF $VM1_IP/24 up
ip netns exec ns0 ip n replace ${VM2_IP} dev $VF lladdr 11:22:33:44:55:77

ovs-vsctl add-br brv-1
ovs-vsctl add-port brv-1 $REP
ovs-vsctl add-port brv-1 vxlan0 -- set interface vxlan0 type=vxlan options:local_ip=$local_tun options:remote_ip=$remote_tun options:key=42 options:dst_port=4789
ovs-ofctl add-flow brv-1 dl_dst=11:11:11:11:11:11,actions=drop
ovs-ofctl add-flow brv-1 in_port=1,icmp,action=2
ovs-ofctl add-flow brv-1 in_port=2,icmp,action=1


function check_offloaded_rules() {
    local count=$1
    title " - check for $count offloaded rules"
    RES="ovs_dpctl_dump_flows | grep 0x0800 | grep -v drop"
    eval $RES
    RES=`eval $RES | wc -l`
    if (( RES == $count )); then success; else err; fi
}

start_check_syndrome
title "Test OVS vxlan"

# generate traffic though it will fail as we have fake destination
ip netns exec ns0 ping -q -c 10 -i 0.2 -w 2 $VM2_IP &>/dev/null

# since we only have encap side right now we should see 1 offloaded rule
check_offloaded_rules 1

title " - verify rule in hw"
i=0 && mlxdump -d $PCI fsdump --type FT --gvmi=$i --no_zero > /tmp/port$i || err "mlxdump failed"
a=`grep "outer_headers.dmac_15_0\s*:0x5577" /tmp/port0`
if [ -z "$a" ]; then
    err "Cannot find rule in HW"
else
    success
fi

check_syndrome
cleanup
test_done
