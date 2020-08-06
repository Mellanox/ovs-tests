#!/bin/bash
#
# Verify adding vxlan rule in multipath env uses the expected 2 neigh entries.
#
# Bug SW #1318772: [ASAP-ECMP MLNX OFED] Traffic not offloaded after failover and failback
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

function add_vxlan_rule() {
    local local_ip="$1"
    local remote_ip="$2"

    echo "local_ip $local_ip remote_ip $remote_ip"
    reset_tc $REP

    tc_filter add dev $REP protocol arp parent ffff: prio 1 \
        flower dst_mac $dst_mac skip_sw \
        action tunnel_key set \
            id $id src_ip ${local_ip} dst_ip ${remote_ip} dst_port ${dst_port} \
        action mirred egress redirect dev vxlan1
}

function verify_neigh() {
    local nn=$@
    local a
    local e=0

    echo "verify neigh entry"

    for i in $nn ; do
        a=`ip n show $i | grep -v FAILED`
        if [ -z "$a" ]; then
            e=1
            err "Expected to find neigh $i"
        else
            echo $a
        fi
    done

    a=`ip n show $remote_ip | grep -v FAILED`
    if [ -n "$a" ]; then
        e=1
        err "Not expected neigh entry: $a"
    fi

    [ $e -eq 0 ] && success
}

function config() {
    config_ports
    config_vxlan
}

function test_add_multipath_rule() {
    config_multipath_route
    is_vf_lag_active || return 1
    ip r show $net
    add_vxlan_rule $local_ip $remote_ip
    verify_neigh $n1 $n2
    reset_tc $REP
}

function test_add_multipath_rule_route1_missing() {
    config_multipath_route
    ip r r $net nexthop via $n2 dev $dev2
    ip r show $net
    add_vxlan_rule $local_ip $remote_ip
    verify_neigh $n2
    reset_tc $REP
}

function test_add_multipath_rule_route2_missing() {
    config_multipath_route
    ip r r $net nexthop via $n1 dev $dev1
    ip r show $net
    add_vxlan_rule $local_ip $remote_ip
    verify_neigh $n1
    reset_tc $REP
}

function test_add_multipath_rule_route1_dead() {
    config_multipath_route
    ifconfig $dev1 down
    ip r show $net
    add_vxlan_rule $local_ip $remote_ip
    verify_neigh $n2
    reset_tc $REP
}

function test_add_multipath_rule_route2_dead() {
    config_multipath_route
    ifconfig $dev2 down
    ip r show $net
    add_vxlan_rule $local_ip $remote_ip
    verify_neigh $n1
    reset_tc $REP
}

function do_test() {
    title $1
    eval $1
}


cleanup
config

do_test test_add_multipath_rule

do_test test_add_multipath_rule_route1_dead
do_test test_add_multipath_rule_route2_dead

# relevant when we fail for gateway 0.0.0.0
do_test test_add_multipath_rule_route1_missing
do_test test_add_multipath_rule_route2_missing

echo "cleanup"
ip link set dev $dev1 up
ip link set dev $dev2 up
cleanup
config_multipath_route
cleanup
deconfig_ports
test_done
