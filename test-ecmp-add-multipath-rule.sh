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

function getnet() {
    echo `ipcalc -n $1 | cut -d= -f2`/24
}

net=`getnet $remote_ip/24`

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
    disable_sriov
    enable_sriov
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
n1=38.2.10.1
n2=38.1.10.1

function config_multipath_route() {
    echo "config multipath route"
    ip l add dev dummy9 type dummy &>/dev/null
    ifconfig dummy9 $local_ip/24
    ifconfig ens1f0 38.2.10.60/24
    ifconfig ens1f1 38.1.10.60/24
    ip r r $net nexthop via $n1 dev $dev1 nexthop via $n2 dev $dev2
    ip n del $n1 dev $dev1 &>/dev/null
    ip n del $n2 dev $dev2 &>/dev/null
}

function verify_neigh() {
    local a
    a=`ip n show $n1 | grep -v FAILED`
    [ -z "$a" ] && err "Expected to find neigh $n1" || echo $a
    a=`ip n show $n2 | grep -v FAILED`
    [ -z "$a" ] && err "Expected to find neigh $n2" || echo $a
}

function config() {
    enable_multipath_and_sriov
    enable_switchdev $NIC
    enable_switchdev $NIC2
    bind_vfs $NIC
    config_vxlan
}

function test_add_multipath_rule() {
    config_multipath_route
    add_vxlan_rule $local_ip $remote_ip
    verify_neigh
    reset_tc_nic $REP
}

function test_add_multipath_rule_route1() {
    config_multipath_route
    ip r r $net nexthop via $n1 dev $dev1
    add_vxlan_rule $local_ip $remote_ip
    verify_neigh
    reset_tc_nic $REP
}

function test_add_multipath_rule_route2() {
    config_multipath_route
    ip r r $net nexthop via $n2 dev $dev2
    add_vxlan_rule $local_ip $remote_ip
    verify_neigh
    reset_tc_nic $REP
}

function do_test() {
    title $1
    eval $1
}


cleanup
config

do_test test_add_multipath_rule
do_test test_add_multipath_rule_route1
do_test test_add_multipath_rule_route2
cleanup
test_done
