#!/bin/bash
#
# Bug SW #1133828: syndrome of invalid encap header id when adding flow without valid neigh
# Bug SW #1120257: KASAN: double-free or invalid-free in mlx5e_detach_encap.isra.16+0x2bd/0x420 [mlx5_core]
#

NIC=${1:-ens5f0}

my_dir="$(dirname "$0")"
. $my_dir/common.sh

REP=`get_rep 0`

local_ip="2.2.2.2"
remote_ip="2.2.2.3"
dst_mac="e4:1d:2d:fd:8b:02"
flag=skip_sw
dst_port=1234
id=98


function cleanup() {
    ip -4 link del dev vxlan1 2> /dev/null
    ip -4 link add vxlan1 type vxlan id $id dev $NIC dstport $dst_port
    ip -4 link set vxlan1 up
    ip n del ${remote_ip} dev $NIC 2>/dev/null
    ip addr flush dev $NIC
}

cleanup
ifconfig $NIC down
ifconfig $NIC ${local_ip}/24 up

start_check_syndrome

# tunnel key set
reset_tc $NIC
reset_tc $REP

tc filter add dev $REP protocol arp parent ffff: \
    flower dst_mac ff:ff:ff:ff:ff:ff $flag \
    action tunnel_key set \
        id $id src_ip ${local_ip} dst_ip ${remote_ip} dst_port ${dst_port} \
    action mirred egress redirect dev vxlan1

tc filter add dev $REP protocol arp parent ffff: \
    flower dst_mac $dst_mac $flag \
    action tunnel_key set \
        id $id src_ip ${local_ip} dst_ip ${remote_ip} dst_port ${dst_port} \
    action mirred egress redirect dev vxlan1

tc filter add dev $REP protocol ip parent ffff: \
    flower dst_mac $dst_mac $flag \
    action tunnel_key set \
        id $id src_ip ${local_ip} dst_ip ${remote_ip} dst_port ${dst_port} \
    action mirred egress redirect dev vxlan1

# tunnel key unset
reset_tc vxlan1

tc filter add dev vxlan1 protocol ip parent ffff: \
    flower $flag enc_src_ip ${remote_ip} enc_dst_ip ${local_ip} \
        enc_key_id $id enc_dst_port ${dst_port} \
    action tunnel_key unset \
    action mirred egress redirect dev $REP

tc filter add dev vxlan1 protocol arp parent ffff: \
    flower $flag enc_src_ip ${remote_ip} enc_dst_ip ${local_ip} \
    enc_key_id $id enc_dst_port ${dst_port} \
    action tunnel_key unset \
    action mirred egress redirect dev $REP

# add change evets
echo "forcing addr change 1"
sleep 5
ip n replace ${remote_ip} dev $NIC lladdr 11:22:33:44:55:66

echo "forcing addr change 2"
sleep 5
ip n replace ${remote_ip} dev $NIC lladdr 11:22:33:44:55:99

cleanup
check_kasan
check_syndrome
test_done
