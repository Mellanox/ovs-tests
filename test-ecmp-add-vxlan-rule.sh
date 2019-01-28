#!/bin/bash
#
# Verify adding vxlan encap+decap rules in multipath env are in hw
#
# Bug SW #1462924: Failed to add vxlan decap rule in ecmp mode
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-ecmp.sh

require_mlxdump

local_ip="39.0.10.60"
remote_ip="36.0.10.180"
dst_mac="e4:1d:2d:fd:8b:02"
dst_port=4789
id=98
net=`getnet $remote_ip 24`
[ -z "$net" ] && fail "Missing net"


function cleanup() {
    ip link del dev vxlan1 2> /dev/null
    ip n del ${remote_ip} dev $NIC 2>/dev/null
    ip n del ${remote_ip6} dev $NIC 2>/dev/null
    ifconfig $NIC down
    ifconfig $NIC2 down
    ip addr flush dev $NIC
    ip addr flush dev $NIC2
    ip l del dummy9 &>/dev/null
    ip r d $net &>/dev/null
}

function config_vxlan() {
    echo "config vxlan dev"
    ip link add vxlan1 type vxlan id $id dev $NIC dstport $dst_port
    ip link set vxlan1 up
    ip addr add ${local_ip}/24 dev $NIC
    tc qdisc add dev vxlan1 ingress
}

function add_vxlan_rule() {
    local local_ip="$1"
    local remote_ip="$2"

    echo "local_ip $local_ip remote_ip $remote_ip"

    # tunnel key set
    ifconfig $NIC up
    reset_tc $NIC
    reset_tc $REP

    tc_filter add dev $REP protocol arp parent ffff: prio 1 \
        flower dst_mac $dst_mac skip_sw \
        action tunnel_key set \
            id $id src_ip ${local_ip} dst_ip ${remote_ip} dst_port ${dst_port} \
        action mirred egress redirect dev vxlan1

    tc_filter add dev vxlan1 protocol arp parent ffff: prio 2 \
        flower src_mac $dst_mac skip_sw \
        enc_key_id $id enc_src_ip ${remote_ip} enc_dst_ip ${local_ip} enc_dst_port ${dst_port} \
        action tunnel_key unset \
        action mirred egress redirect dev $REP
}

function verify_rule_in_hw() {
    echo "verify rules in hw"
    i=0 && mlxdump -d $PCI fsdump --type FT --gvmi=$i --no_zero > /tmp/port$i || err "mlxdump failed"
    i=1 && mlxdump -d $PCI fsdump --type FT --gvmi=$i --no_zero > /tmp/port$i || err "mlxdump failed"
    for i in 0 1 ; do
        if ! cat /tmp/port$i | grep -e "action.*:0x1c" ; then
            err "Missing encap rule for port$i"
        fi
        if ! cat /tmp/port$i | grep -e "action.*:0x2c" ; then
            err "Missing decap rule for port$i"
        fi
    done
}

function config() {
    config_ports
    ifconfig $NIC up
    ifconfig $NIC2 up
    config_vxlan
}

function test_add_multipath_rule() {
    config_multipath_route
    vf_lag_is_active
    ip r show $net
    add_vxlan_rule $local_ip $remote_ip
    verify_rule_in_hw
    reset_tc_nic $REP
}

function do_test() {
    title $1
    eval $1
}


cleanup
config
do_test test_add_multipath_rule
echo "cleanup"
cleanup
deconfig_ports
test_done
