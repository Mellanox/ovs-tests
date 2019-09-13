#!/bin/bash
#
# Verify different tunnels with same properties get different encap_ids
#
# Bug SW #1707536: [upstream] encap traffic via wrong tunnel if has the same tunnel properties
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

config_sriov 2
enable_switchdev_if_no_rep $REP
unbind_vfs
bind_vfs

local_ip="39.0.10.60"
remote_ip="39.0.10.180"
dst_mac1="e4:1d:2d:fd:8b:02"
dst_mac2="e4:1d:2d:fd:8b:03"
dst_port=4789
id=98

#set -x

function cleanup() {
    ip link del dev vxlan1 2> /dev/null
    ip link del dev gre1 2> /dev/null
    ip n del ${remote_ip} dev $NIC 2>/dev/null
    ifconfig $NIC down
    ip addr flush dev $NIC
    reset_tc $NIC
}

function config_vxlan() {
    echo "config vxlan dev"
    ip link add vxlan1 type vxlan id $id dev $NIC dstport $dst_port
    ip link set vxlan1 up
}

function config_gre() {
    echo "config gre dev"
    ip link add gre1 type gretap key $id dev $NIC
    ip link set gre1 up
}

function add_tunnel_encap_rule() {
    local local_ip="$1"
    local remote_ip="$2"
    local dev="$3"
    local dst_mac="$4"

    echo "local_ip $local_ip remote_ip $remote_ip"

    # tunnel key set
    echo tc_filter add dev $REP protocol ip parent ffff: prio 1 \
        flower dst_mac $dst_mac skip_sw \
        action tunnel_key set \
            id $id src_ip ${local_ip} dst_ip ${remote_ip} dst_port ${dst_port} nocsum \
        action mirred egress redirect dev $dev
    tc_filter add dev $REP protocol ip parent ffff: prio 1 \
        flower dst_mac $dst_mac skip_sw \
        action tunnel_key set \
            id $id src_ip ${local_ip} dst_ip ${remote_ip} dst_port ${dst_port} nocsum \
        action mirred egress redirect dev $dev
}

function verify_different_encap_ids() {
    title "- verify different encap ids"

    i=0 && mlxdump -d $PCI fsdump --type FT --gvmi=$i > /tmp/port$i || err "mlxdump failed"
    fte_lines=`grep -n FTE /tmp/port$i -m2 | cut -d ":" -f1`
    fte0_line=`echo $fte_lines | cut -d " " -f1`
    fte1_line=`echo $fte_lines | cut -d " " -f2`
    fte_len=$((fte1_line-fte0_line))
    encap_ids=`grep -e "action.*:0x1c" -A $fte_len /tmp/port$i -m2 | grep packet_reformat_id | cut -d ":" -f2`
    encap0=`echo $encap_ids | cut -d " " -f1`
    encap1=`echo $encap_ids | cut -d " " -f2`

    if [ "$encap0" == "$encap1" ]; then
        fail "Both VXLAN and GRE has the same packet_reformat_id ($encap0)"
    else
        success
    fi
}

function test_add_encap_rule() {
    ip n r $remote_ip dev $NIC lladdr e4:1d:2d:31:eb:08
    ip r show dev $NIC
    ip n show $remote_ip
    reset_tc $NIC $REP $dev
    add_tunnel_encap_rule $local_ip $remote_ip vxlan1 $dst_mac1
    add_tunnel_encap_rule $local_ip $remote_ip gre1 $dst_mac2
    verify_different_encap_ids
    reset_tc $REP
}

function do_test() {
    title $1
    eval $1
}


cleanup
config_vxlan
config_gre
ifconfig $NIC $local_ip/24 up
do_test test_add_encap_rule

cleanup
test_done
