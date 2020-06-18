#!/bin/bash
#
# Verify adding vxlan encap rule use right route device and neigh entry.
#
# Bug SW #1647028: [upstream] encap created when uplink is down is wrong
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

config_sriov 2
enable_switchdev
unbind_vfs
bind_vfs

local_ip="39.0.10.60"
remote_ip="39.0.10.180"
dst_mac="e4:1d:2d:fd:8b:02"
dst_port=4789
id=98


function cleanup() {
    ip link del dev vxlan1 2> /dev/null
    ip n del ${remote_ip} dev $NIC 2>/dev/null
    ifconfig $NIC down
    ip addr flush dev $NIC
    reset_tc $NIC
}

function config_vxlan() {
    echo "config vxlan dev"
    ip link add vxlan1 type vxlan id $id dev $NIC dstport $dst_port
    ip link set vxlan1 up
    ifconfig $NIC $local_ip/24 up
}

function add_vxlan_rule() {
    local local_ip="$1"
    local remote_ip="$2"

    echo "local_ip $local_ip remote_ip $remote_ip"

    reset_tc $NIC $REP vxlan1

    # tunnel key set
    tc_filter add dev $REP protocol arp parent ffff: prio 1 \
        flower dst_mac $dst_mac skip_sw \
        action tunnel_key set \
            id $id src_ip ${local_ip} dst_ip ${remote_ip} dst_port ${dst_port} \
        action mirred egress redirect dev vxlan1
}

function verify_rule_in_hw() {
    local not=$1
    local e=0

    title "- verify rule $not in hw"

    i=0 && mlxdump -d $PCI fsdump --type FT --gvmi=$i --no_zero > /tmp/port$i || err "mlxdump failed"
    if [ -z "$not" ]; then
        if ! cat /tmp/port$i | grep -e "action.*:0x1c" ; then
            e=1
            err "Missing encap rule on port$i"
        fi
    else
        if cat /tmp/port$i | grep -e "action.*:0x1c" ; then
            e=1
            err "Didn't expect encap rule on port$i"
        fi
    fi

    [ $e -eq 0 ] && success
}

function verify_neigh() {
    echo "verify neigh"
    ip n show dev $NIC

    local a=`ip n show $remote_ip | grep -v FAILED`
    [ -z "$a" ] && err "Expected to find neigh $remote_ip" || echo $a
}

function test_add_encap_rule() {
    ip n r $remote_ip dev $NIC lladdr e4:1d:2d:31:eb:08
    ip r show dev $NIC
    ip n show $remote_ip
    add_vxlan_rule $local_ip $remote_ip
    verify_neigh
    verify_rule_in_hw
    reset_tc $REP
}

function test_add_encap_rule_neigh_missing() {
    echo "del neigh"
    ip n del $remote_ip dev $NIC
    ip r show dev $NIC
    ip n show $remote_ip
    add_vxlan_rule $local_ip $remote_ip
    verify_neigh
    verify_rule_in_hw not
    reset_tc $REP
}

# this is like route missing
function test_add_encap_rule_tunnel_down() {
    echo "nic down"
    ifconfig $NIC down
    ip r show dev $NIC
    ip n show $remote_ip
    add_vxlan_rule $local_ip $remote_ip
    verify_rule_in_hw not
    reset_tc $REP
}

function do_test() {
    title $1
    eval $1
}


cleanup
config_vxlan
do_test test_add_encap_rule
do_test test_add_encap_rule_neigh_missing
do_test test_add_encap_rule_tunnel_down

cleanup
test_done
