#!/bin/bash
#
# Test to verify if we can add vxlan decap rule in skip_sw policy
# Bug SW #1360599: [upstream] decap rule offload attempt with skip_sw fails
#
# IGNORE_FROM_TEST_ALL

my_dir="$(dirname "$0")"
. $my_dir/common.sh

VXLAN=vxlan1
TUN_SRC_V4=20.1.184.1
TUN_DST_V4=20.1.183.1
VM_DST_MAC=e4:11:22:33:44:70

enable_switchdev
bind_vfs

title "Verify we can add vxlan decap rule in skip_sw policy"

ip link del $VXLAN &>/dev/null
ip link add $VXLAN type vxlan dstport 4789 external udp6zerocsumrx || fail "Failed to create vxlan interface"
ifconfig $VXLAN up
reset_tc $VXLAN
reset_tc $NIC
ip addr add dev $NIC $TUN_SRC_V4/16


# decap rule set on the vxlan device
echo "-- add vxlan decap rule"
tc_filter add dev $VXLAN protocol ip parent ffff: prio 10\
                flower skip_sw enc_src_ip $TUN_DST_V4 enc_dst_ip $TUN_SRC_V4 \
                enc_key_id 100 enc_dst_port 4789 src_mac $VM_DST_MAC \
                action tunnel_key unset \
                action mirred egress redirect dev $REP

reset_tc $VXLAN
reset_tc $NIC
ip addr flush dev $NIC
ip link del $VXLAN

test_done
