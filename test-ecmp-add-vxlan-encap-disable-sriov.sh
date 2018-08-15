#!/bin/bash
#
# Add VXLAN encap rule in ECMP mode and disable sriov first on pf1 and then pf0
#
# Bug SW #1504474: [ECMP] mlx5_core crash in mlx5e_detach_encap
#

NIC=${1:-ens5f0}

my_dir="$(dirname "$0")"
. $my_dir/common.sh

config_sriov 2
require_mlxdump
require_multipath_support
reset_tc_nic $NIC

local_ip="39.0.10.60"
remote_ip="36.0.10.180"
dst_mac="e4:1d:2d:fd:8b:02"
flag=skip_sw
dst_port=4789
id=98
net=`getnet $remote_ip 24`
[ -z "$net" ] && fail "Missing net"


function disable_sriov() {
    echo "- Disable SRIOV"
    echo 0 > /sys/class/net/$NIC/device/sriov_numvfs
    echo 0 > /sys/class/net/$NIC2/device/sriov_numvfs
}

function enable_sriov() {
    echo "- Enable SRIOV"
    echo 2 > /sys/class/net/$NIC/device/sriov_numvfs
    echo 2 > /sys/class/net/$NIC2/device/sriov_numvfs
}

function enable_multipath_and_sriov() {
    echo "- Enable multipath"
    a=`cat /sys/class/net/$NIC/device/sriov_numvfs`
    b=`cat /sys/class/net/$NIC2/device/sriov_numvfs`
    if [ $a -eq 0 ] || [ $b -eq 0 ]; then
        disable_sriov
        enable_sriov
    fi
    unbind_vfs $NIC
    unbind_vfs $NIC2
    enable_multipath || err "Failed to enable multipath"
}

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
        flower dst_mac $dst_mac $flag \
        action tunnel_key set \
            id $id src_ip ${local_ip} dst_ip ${remote_ip} dst_port ${dst_port} \
        action mirred egress redirect dev vxlan1

    tc_filter add dev vxlan1 protocol arp parent ffff: prio 2 \
        flower src_mac $dst_mac $flag \
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

dev1=$NIC
dev2=$NIC2
dev1_ip=38.2.10.60
dev2_ip=38.1.10.60
n1=38.2.10.1
n2=38.1.10.1

function config_multipath_route() {
    echo "config multipath route"
    ip l add dev dummy9 type dummy &>/dev/null
    ifconfig dummy9 $local_ip/24
    ifconfig $NIC $dev1_ip/24
    ifconfig $NIC2 $dev2_ip/24
    ip r r $net nexthop via $n1 dev $dev1 nexthop via $n2 dev $dev2
    ip n del $n1 dev $dev1 &>/dev/null
    ip n del $n2 dev $dev2 &>/dev/null
    ip n del $remote_ip dev $dev1 &>/dev/null
    ip n del $remote_ip dev $dev2 &>/dev/null
    ip n add $n1 dev $dev1 lladdr e4:1d:2d:31:eb:08
    ip n add $n2 dev $dev2 lladdr e4:1d:2d:31:eb:08
}

function config() {
    enable_multipath_and_sriov
    wa_reset_multipath
    bind_vfs $NIC
    config_vxlan
}

function test_add_encap_and_disable_sriov() {
    title "Add VXLAN ENCAP rule in ECMP mode and disable sriov"
    config_multipath_route
    ip r show $net
    add_vxlan_rule $local_ip $remote_ip
    verify_rule_in_hw
    title "- disable sriov $NIC2"
    config_sriov 0 $NIC2
    title "- disable sriov $NIC"
    config_sriov 0 $NIC
}

cleanup
config
test_add_encap_and_disable_sriov

cleanup
test_done
