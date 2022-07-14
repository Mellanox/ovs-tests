#!/bin/bash
#
# Add VXLAN encap rule in ECMP mode and reload modules
#
# Bug SW #3138616: [ASAP, OFED 5.7, ECMP] kernel panic when reloading modules after adding vlxan enacp rule in ECMP mode
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-ecmp.sh

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
trap cleanup EXIT

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

function config() {
    config_ports
    ifconfig $NIC up
    ifconfig $NIC2 up
    config_vxlan
}

function test_add_encap_and_reload_modules() {
    title "Add multipath vxlan encap rule and disable sriov"
    config_multipath_route
    is_vf_lag_active || return 1
    ip r show $net
    add_vxlan_rule $local_ip $remote_ip
    reload_modules
}

cleanup
config
test_add_encap_and_reload_modules
trap - EXIT
cleanup
test_done
