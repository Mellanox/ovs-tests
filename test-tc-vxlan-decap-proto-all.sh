#!/bin/bash
#
# Test vxlan decap rule with proto all.
#
# Bug SW #1572366: [TC] failed to create VXLAN decapsulation tc rule - syndrome 0x7e1579
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

VXLAN=vxlan1
TUN_SRC_V4=20.1.184.1
TUN_DST_V4=20.1.183.1
VM_DST_MAC=e4:11:22:33:44:70

enable_switchdev_if_no_rep $REP
bind_vfs

title "Verify we can add vxlan decap rule with proto all"

ip link del $VXLAN &>/dev/null
ip link add $VXLAN type vxlan dstport 4789 external udp6zerocsumrx || fail "Failed to create vxlan interface"
ip addr add dev $NIC $TUN_SRC_V4/16
ifconfig $VXLAN up
reset_tc $VXLAN
reset_tc $NIC

start_check_syndrome
# decap rule set on the vxlan device
echo "-- add vxlan decap rule"
tc_filter add dev $VXLAN protocol all parent ffff: prio 2 \
                flower enc_src_ip $TUN_DST_V4 enc_dst_ip $TUN_SRC_V4 \
                enc_key_id 100 enc_dst_port 4789 \
                action tunnel_key unset \
                action mirred egress redirect dev $REP

if [ $? -eq 0 ]; then
    tc_filter show dev $VXLAN ingress prio 2 | grep -q -w in_hw || err "Decap rule not in hw"
fi

check_syndrome
reset_tc $VXLAN
reset_tc $NIC
ip addr flush dev $NIC
ip link del $VXLAN

test_done
