#!/bin/bash
#
# Test to verify with can offload decap rule with enc_key_id/enc_dst_port only.
# i.e. without enc_src_ip and enc_dst_ip.
#
# [PATCH] net/mlx5e: Allow matching only enc_key_id/enc_dst_port for decapsulation action
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

VXLAN=vxlan1
TUN_SRC_V4=20.1.184.1
VM_DST_MAC=e4:11:22:33:44:70

enable_switchdev_if_no_rep $REP
bind_vfs

function cleanup() {
    ip link del $VXLAN &>/dev/null
    ip addr flush dev $NIC
}
trap cleanup EXIT

function do_test() {
    title "Verify vxlan decap rule matching only enc_key and enc_dst_port"

    cleanup
    ip link add $VXLAN type vxlan dstport 4789 external
    [ $? -ne 0 ] && fail "Failed to create vxlan interface"
    ifconfig $VXLAN up
    reset_tc $NIC $REP $VXLAN
    ip addr add dev $NIC $TUN_SRC_V4/16

    tc_filter add dev $VXLAN protocol ip parent ffff: prio 1 flower \
                    enc_key_id 100 enc_dst_port 4789 src_mac $VM_DST_MAC \
                    action tunnel_key unset \
                    action mirred egress redirect dev $REP

    verify_in_hw $VXLAN 1
}

do_test
test_done
