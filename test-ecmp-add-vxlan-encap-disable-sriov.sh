#!/bin/bash
#
# Add VXLAN encap rule in ECMP mode and disable sriov first on pf1 and then pf0
#
# Bug SW #1504474: [ECMP] mlx5_core crash in mlx5e_detach_encap
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
    cleanup_multipath
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

}

function verify_rule_in_hw() {
    local i
    local a

    title "verify rule in hw"

    for i in 0 1 ; do
        mlxdump -d $PCI fsdump --type FT --gvmi=$i --no_zero > /tmp/port$i || err "mlxdump failed"

        a=`cat /tmp/port$i | grep -e "action.*:0x1c"`
        if [ -n "$a" ]; then
            success2 "Found encap rule for port$i"
        else
            err "Missing encap rule for port$i"
        fi
    done
}

function config() {
    config_ports
    ifconfig $NIC up
    ifconfig $NIC2 up
    config_vxlan
}

function test_add_encap_and_disable_sriov() {
    title "Add multipath vxlan encap rule and disable sriov"
    config_multipath_route
    is_vf_lag_active || return 1
    ip r show $net
    add_vxlan_rule $local_ip $remote_ip
    verify_rule_in_hw
    title "- disable sriov $NIC2"
    config_sriov 0 $NIC2
    title "- disable sriov $NIC"
    config_sriov 0 $NIC
    title "- enable sriov $NIC"
    config_sriov 2 $NIC
}

cleanup
config
test_add_encap_and_disable_sriov
echo "cleanup"
cleanup
#we disable sriov in the test so no need to call deconfig_ports
test_done
