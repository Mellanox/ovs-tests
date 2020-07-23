#!/bin/bash
#
# Test forwarding traffic received from uplink back to uplink after encapsulation
#

my_dir="$(dirname "$0")"
source $my_dir/common.sh

# set test variables
UPLSRC=$NIC
UPLDEST=$NIC
TUN=vx0
LOCAL_TUN_IP=8.8.8.21
REMOTE_TUN_IP=8.8.8.24
DPORT=4789
TUNID=123

function cleanup() {
    reset_tc $UPLSRC &>/dev/null
    ip link del dev $TUN &>/dev/null
    ip neigh del $REMOTE_TUN_IP dev $UPLDEST &>/dev/null
    ip addr del ${LOCAL_TUN_IP}/24 dev $UPLDEST &>/dev/null
}
trap cleanup EXIT

title "Test redirect rule traffic from uplink of esw0 back to the same uplink (after encap)"
enable_switchdev

# bring up interfaces
ip link set up dev $UPLSRC
ip link set up dev $UPLDEST

ip link add dev $TUN type vxlan id $TUNID dstport $DPORT
ip link set up dev $TUN
ip addr add ${LOCAL_TUN_IP}/24 dev $UPLDEST
ip neigh add $REMOTE_TUN_IP lladdr 00:11:22:33:44:55 dev $UPLDEST

reset_tc $UPLSRC
tc_filter add dev $UPLSRC protocol ip prio 1 root flower dst_ip 11.12.13.14 skip_sw action tunnel_key set src_ip ${LOCAL_TUN_IP} dst_ip $REMOTE_TUN_IP id $TUNID dst_port $DPORT action mirred egress redirect dev $TUN

mode=`get_flow_steering_mode $NIC`
if [ "$mode" == "dmfs" ]; then
    title "Check hardware tables... "
    mlxdump -d $PCI fsdump --type FT > /tmp/_fsdump
    if cat /tmp/_fsdump | grep -B 44 -A 57 "outer_headers.dst_ip_31_0.*:0x0b0c0d0e" | grep "destination\[0\].destination_type.*:FLOW_TABLE_" > /dev/null; then
        success
    else
        err
    fi
fi

cleanup
test_done
