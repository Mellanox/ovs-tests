#!/bin/bash
#
# Verify adding vxlan rule in multipath env uses the expected 2 neigh entries.
#
# Bug SW #1318772: [ASAP-ECMP MLNX OFED] Traffic not offloaded after failover and failback
#

NIC=${1:-ens5f0}

my_dir="$(dirname "$0")"
. $my_dir/common.sh

config_sriov 2
require_multipath_support
reset_tc_nic $NIC

local_ip="39.0.10.60"
remote_ip="36.0.10.180"
dst_mac="e4:1d:2d:fd:8b:02"
flag=skip_sw
dst_port=4789
id=98
net=`getnet $remote_ip 24`

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
}

function verify_neigh() {
    local nn=$@
    local a

    for i in $nn ; do
        a=`ip n show $i | grep -v FAILED`
        [ -z "$a" ] && err "Expected to find neigh $i" || echo $a
    done

    a=`ip n show $remote_ip | grep -v FAILED`
    [ -n "$a" ] && echo $a && err "Not expected neigh entry for $remote_ip"
}

function _reset_multipath() {
    # we currently switch to legacy and back because of an issue
    # when multipath is ready.
    # Bug SW #1391181: [ASAP MLNX OFED] Enabling multipath only becomes enabled
    # when changing mode from legacy to switchdev
    enable_legacy $NIC
    enable_legacy $NIC2
    enable_switchdev $NIC
    enable_switchdev $NIC2
}

function config() {
    enable_multipath_and_sriov
    _reset_multipath
    bind_vfs $NIC
    config_vxlan
}

function test_add_multipath_rule() {
    config_multipath_route
    ip r show $net
    add_vxlan_rule $local_ip $remote_ip
    verify_neigh $n1 $n2
    reset_tc_nic $REP
}

function test_add_multipath_rule_route1_missing() {
    config_multipath_route
    ip r r $net nexthop via $n1 dev $dev1
    ip r show $net
    add_vxlan_rule $local_ip $remote_ip
    verify_neigh $n1
    reset_tc_nic $REP
}

function test_add_multipath_rule_route2_missing() {
    config_multipath_route
    ip r r $net nexthop via $n2 dev $dev2
    ip r show $net
    add_vxlan_rule $local_ip $remote_ip
    verify_neigh $n2
    reset_tc_nic $REP
}

function test_add_multipath_rule_route1_dead() {
    config_multipath_route
    ifconfig $dev2 down
    ip r show $net
    add_vxlan_rule $local_ip $remote_ip
    verify_neigh $n1
    reset_tc_nic $REP
}

function test_add_multipath_rule_route2_dead() {
    config_multipath_route
    ifconfig $dev1 down
    ip r show $net
    add_vxlan_rule $local_ip $remote_ip
    verify_neigh $n2
    reset_tc_nic $REP
}

function do_test() {
    title $1
    eval $1
}


cleanup
config

do_test test_add_multipath_rule
do_test test_add_multipath_rule_route1_missing
do_test test_add_multipath_rule_route2_missing
do_test test_add_multipath_rule_route1_dead
do_test test_add_multipath_rule_route2_dead

cleanup
test_done
