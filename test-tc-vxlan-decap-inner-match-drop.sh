#!/bin/bash
#
# Reproduce issue vxlan rule without decap action (i.e. drop) matching on inner
# headers.
#
# Bug SW #1815314: [ASAP] - Got syndrome while restart openvswitch service
#   with heavy traffic in background over VF LAG LACP configuration syndrome (0x17faa8)
#
#   BAD_PARAM           | 0x17FAA8 |  create_flow_group: inner_headers valid bit
#                                       isn't set, but headers are not reserved
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
    title "Verify vxlan drop rule"

    cleanup
    ip link add $VXLAN type vxlan dstport 4789 external
    [ $? -ne 0 ] && fail "Failed to create vxlan interface"
    ifconfig $VXLAN up
    reset_tc $NIC $REP $VXLAN
    ip addr add dev $NIC $TUN_SRC_V4/16

    tc_filter add dev $VXLAN protocol ip parent ffff: prio 1 flower \
                    enc_key_id 100 enc_dst_port 4789 src_mac $VM_DST_MAC \
                    enc_src_ip $TUN_SRC_V4 \
                    action drop

    verify_in_hw $VXLAN 1
}

start_check_syndrome
do_test
check_syndrome
test_done
