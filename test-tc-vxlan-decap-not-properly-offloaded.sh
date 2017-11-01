#!/bin/bash
#
# Test to verify rule is being deleted from FW when deleted from TC.
# Bug SW #1164801: e-switch vxlan decap flows are not properly offloaded
#

NIC=${1:-ens5f0}
FILTER=${FILTER}

my_dir="$(dirname "$0")"
. $my_dir/common.sh

get_mst_dev

VXLAN=vxlan_sys_4789
TC=tc
IP=ip
SKIP_DEC=skip_sw
TUN_SRC_V4=20.1.184.1
TUN_DST_V4=20.1.183.1
VM_DST_MAC=e4:11:22:33:44:70
REP=`get_rep 0`
if [ -z "$REP" ]; then
    fail "Missing rep $rep"
fi

$IP link add $VXLAN type vxlan dstport 4789 external udp6zerocsumrx
ifconfig $VXLAN up
tc qdisc add dev $VXLAN ingress

reset_tc_nic $NIC
reset_tc_nic $REP

$IP addr add dev $NIC $TUN_SRC_V4/16

rm -fr /tmp/fsdump_before_add /tmp/fsdump_after_add /tmp/fsdump_after_del

mlxdump -d $DEV fsdump --type FT --no_zero=true > /tmp/fsdump_before_add || err "mlxdump failed"

# decap rule set on the vxlan device
title "Add vxlan decap rule"
$TC filter add dev $VXLAN protocol ip parent ffff: prio 10\
                flower enc_src_ip $TUN_DST_V4 enc_dst_ip $TUN_SRC_V4 \
                enc_key_id 100 enc_dst_port 4789 src_mac $VM_DST_MAC \
                $SKIP_DEC \
                action tunnel_key unset \
                action mirred egress redirect dev $REP || err "TC command failed"

mlxdump -d $DEV fsdump --type FT --no_zero=true > /tmp/fsdump_after_add || err "mlxdump failed"

DIF=`diff -u /tmp/fsdump_before_add /tmp/fsdump_after_add`

if [ -z "$DIF" ]; then
    err "Empty diff /tmp/fsdump_before_add /tmp/fsdump_after_add"
fi

title "Delete ingress qdisc"
$TC qdisc del dev $REP ingress
$TC qdisc del dev $VXLAN ingress

mlxdump -d $DEV fsdump --type FT --no_zero=true > /tmp/fsdump_after_del || err "mlxdump failed"

title "Verify rule deleted from HW"
DIF=`diff -u /tmp/fsdump_after_add /tmp/fsdump_after_del`

if [ -z "$DIF" ]; then
    err "Empty diff /tmp/fsdump_after_add /tmp/fsdump_after_del"
fi
 
ip addr flush dev $NIC
ip addr flush dev $REP
ip link del $VXLAN

test_done
