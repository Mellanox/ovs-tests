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
    cleanup_multipath
}

function add_vxlan_rule() {
    local local_ip="$1"
    local remote_ip="$2"

    echo "local_ip $local_ip remote_ip $remote_ip"

    # tunnel key set
    ifconfig $NIC up
    reset_tc $NIC $NIC2 $REP
    tc_test_verbose

    log "add encap rule"
    tc_filter add dev $REP protocol arp parent ffff: prio 1 \
        flower $tc_verbose dst_mac $dst_mac skip_sw \
        action tunnel_key set \
            id $id src_ip ${local_ip} dst_ip ${remote_ip} dst_port ${dst_port} \
        action mirred egress redirect dev vxlan1

    log "add decap rule"
    tc_filter add dev vxlan1 protocol arp parent ffff: prio 2 \
        flower $tc_verbose src_mac $dst_mac \
        enc_key_id $id enc_src_ip ${remote_ip} enc_dst_ip ${local_ip} enc_dst_port ${dst_port} \
        action tunnel_key unset \
        action mirred egress redirect dev $REP
    # some kernels don't support offloading decap skip_sw so dont use it.
    # this test verify later the decap rule is in hw.
}

function verify_rules_in_hw() {
    local i
    local a

    title "verify rules in hw"

    for i in 0 1 ; do
        mlxdump -d $PCI fsdump --type FT --gvmi=$i --no_zero > /tmp/port$i || err "mlxdump failed"

        a=`cat /tmp/port$i | grep -e "action.*:0x1c"`
        if [ -n "$a" ]; then
            success2 "Found encap rule for port$i"
        else
            err "Missing encap rule for port$i"
        fi

        a=`cat /tmp/port$i | grep -e "action.*:0x2c"`
        if [ -n "$a" ]; then
            success2 "Found decap rule for port$i"
        else
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
    is_vf_lag_active || return 1
    ip r show $net
    add_vxlan_rule $local_ip $remote_ip
    verify_rules_in_hw
    reset_tc $REP
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
