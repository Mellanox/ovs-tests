#!/bin/bash
#
# Test vxlan and pedit with gro off on the vxlan interface.
#
# Bug SW #1605385: pedit of src port on vxlan traffic doesn't work
# Bug SW #1658441: [upstream] Cannot find packets after header rewrite of src port when gro is off
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


VM1_IP="7.7.7.1"
VM2_IP="7.7.7.2"

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

    for i in $PORT1 $PORT2 $PORT3 $PORT4 ; do
        ip a flush $i
    done
}

enable_switchdev
unbind_vfs
bind_vfs
require_interfaces VF REP VF2 REP2
PORT1=$VF
PORT2=$REP
PORT3=$VF2
PORT4=$REP2

echo "setup ns"
cleanup

ifconfig $PORT1 $VM1_IP/24 up
ifconfig $PORT2 up
ifconfig $PORT4 $local_tun/24 up

ip netns add ns0
ip link set $PORT3 netns ns0
ip netns exec ns0 ifconfig $PORT3 $remote_tun/24 up

ip netns exec ns0 ip link add name vxlan42 type vxlan id 42 dev $PORT3 remote $local_tun dstport 4789
ip netns exec ns0 ifconfig vxlan42 $VM2_IP/24 up

echo "setup ovs"
ovs-vsctl add-br brv-1
ovs-vsctl add-port brv-1 $PORT2
ovs-vsctl add-port brv-1 vxlan0 -- set interface vxlan0 type=vxlan options:local_ip=$local_tun options:remote_ip=$remote_tun options:key=42 options:dst_port=4789

function check_rules() {
    local count=$1
    title " - check for $count rules"
    RES="ovs_dump_tc_flows | grep 0x0800 | grep -v drop"
    eval $RES
    RES=`eval $RES | wc -l`
    if (( RES == $count )); then success
    else
         ovs_dump_ovs_flows | grep 0x0800 | grep -v drop
         err "rules not offloaded"
    fi
}

ovs-ofctl del-flows brv-1
ovs-ofctl add-flow brv-1 "udp,nw_dst=$VM2_IP,actions=normal"
#ovs-ofctl add-flow brv-1 "udp,nw_dst=$VM1_IP,actions=normal"
ovs-ofctl add-flow brv-1 "udp,nw_dst=$VM1_IP,actions=mod_tp_src=1234,normal"
ovs-ofctl add-flow brv-1 "arp,actions=normal"
ovs-dpctl del-flows

title "Test header rewrite with gro off"

echo "set gro off on vxlan interface"
ethtool -K vxlan_sys_4789 gro off || err "Failed to set gro off"

echo "start tcpdump on $PORT2"
timeout 6 tcpdump -qnnei $PORT2 -c 10 udp and src port 1234 &
pid=$!

echo "generate traffic"
pktgen=$my_dir/scapy-traffic-tester.py
t=6
ip netns exec ns0 $pktgen -l -i vxlan42 --src-ip $VM1_IP --time $((t+1)) &
pid1=$!
sleep 1
$pktgen -i $PORT1 --src-ip $VM1_IP --dst-ip $VM2_IP --time $t
kill $pid1 &>/dev/null
wait $pid1 &>/dev/null

# we expect to be in tc but not in hw. as we support vxlan offload only when using uplink.
check_rules 2

title " - Verify header rewrite of src port"
wait $pid
if [ $? -eq 0 ]; then
    success "Found packets after header rewrite of src port"
else
    err "Cannot find packets after header rewrite of src port"
fi
cleanup
test_done
