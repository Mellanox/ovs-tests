#!/bin/bash
#
# Test to verify rule is being deleted from FW when deleted from TC.
# Bug SW #1164801: e-switch vxlan decap flows are not properly offloaded
#

NIC=${1:-ens5f0}

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_mlxdump

VXLAN=vxlan_sys_4789
TUN_SRC_V4=20.1.184.1
TUN_DST_V4=20.1.183.1
VM_DST_MAC=e4:11:22:33:44:70

enable_switchdev_if_no_rep $REP
bind_vfs

title "Verify vxlan rule is being deleted from FW when deleted from TC"

ip link del $VXLAN &>/dev/null
ip link add $VXLAN type vxlan dstport 4789 external udp6zerocsumrx
[ $? -ne 0 ] && fail "Failed to create vxlan interface"
ifconfig $VXLAN up
tc qdisc add dev $VXLAN ingress

reset_tc $NIC
reset_tc $REP

ip addr add dev $NIC $TUN_SRC_V4/16

rm -fr /tmp/fsdump_before_add /tmp/fsdump_after_add /tmp/fsdump_after_del

echo "-- dump before"
mlxdump -d $PCI fsdump --type FT --no_zero > /tmp/fsdump_before_add || err "mlxdump failed"

# decap rule set on the vxlan device
echo "-- add vxlan decap rule"
tc_filter add dev $VXLAN protocol ip parent ffff: prio 10\
                flower enc_src_ip $TUN_DST_V4 enc_dst_ip $TUN_SRC_V4 \
                enc_key_id 100 enc_dst_port 4789 src_mac $VM_DST_MAC \
                action tunnel_key unset \
                action mirred egress redirect dev $REP

fail_if_err
echo "-- dump after add"
mlxdump -d $PCI fsdump --type FT --no_zero > /tmp/fsdump_after_add || err "mlxdump failed"

DIF=`diff -u /tmp/fsdump_before_add /tmp/fsdump_after_add`

if [ -z "$DIF" ]; then
    err "Empty diff /tmp/fsdump_before_add /tmp/fsdump_after_add"
fi

tc qdisc del dev $REP ingress
tc qdisc del dev $VXLAN ingress

echo "-- dump after del"
mlxdump -d $PCI fsdump --type FT --no_zero > /tmp/fsdump_after_del || err "mlxdump failed"

echo "-- verify rule deleted from HW"
DIF=`diff -u /tmp/fsdump_after_add /tmp/fsdump_after_del`

if [ -z "$DIF" ]; then
    err "Empty diff /tmp/fsdump_after_add /tmp/fsdump_after_del"
fi
 
rm -fr /tmp/fsdump_before_add /tmp/fsdump_after_add /tmp/fsdump_after_del
ip addr flush dev $NIC
ip addr flush dev $REP
ip link del $VXLAN

test_done
