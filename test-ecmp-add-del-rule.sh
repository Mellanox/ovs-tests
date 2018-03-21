#!/bin/bash
#
# Bug SW #1242052: [ECMP] Null pointer dereference when adding encap rule in
# multipath mode and pf0 is in switchdev mode but pf1 is not in sriov mode
#

NIC=${1:-ens5f0}

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_multipath_support
reset_tc_nic $NIC

local_ip="2.2.2.2"
remote_ip="2.2.2.3"
dst_mac="e4:1d:2d:fd:8b:02"
flag=skip_sw
dst_port=1234
id=98

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
    ip addr flush dev $NIC
}

function config_vxlan() {
    ip link add vxlan1 type vxlan id $id dev $NIC dstport $dst_port
    ip link set vxlan1 up
    ip addr add ${local_ip}/24 dev $NIC
}

function add_vxlan_rule() {
    local local_ip="$1"
    local remote_ip="$2"

    echo "local_ip $local_ip remote_ip $remote_ip"

    # tunnel key set
    ifconfig $NIC up
    reset_tc $NIC
    reset_tc $REP

    cmd="tc filter add dev $REP protocol arp parent ffff: \
        flower dst_mac $dst_mac $flag \
        action tunnel_key set \
            id $id src_ip ${local_ip} dst_ip ${remote_ip} dst_port ${dst_port} \
        action mirred egress redirect dev vxlan1"
    echo $cmd
    $cmd || err "Failed to add encap rule"
}


# multipath enabled, sriov mode, and clean
function test_config_sriov_and_clean() {
    enable_multipath_and_sriov
    ifconfig $NIC up
    cleanup
}

# multipath enabled, switchdev mode on pf0 only, add encap rule
function test_add_esw_rule_only_pf0_in_switchdev() {
    enable_multipath_and_sriov
    enable_switchdev
    config_vxlan
    add_vxlan_rule $local_ip $remote_ip
    cleanup
}

# multipath enabled and ready and then disable sriov and enable only pf0 to
# switchdev and verify adding rule doesn't crash the system.
function test_add_esw_rule_after_multipath_was_ready_before() {
    enable_multipath_and_sriov
    enable_switchdev $NIC
    enable_switchdev $NIC2
    disable_sriov
    enable_sriov
    enable_switchdev $NIC
    config_vxlan
    add_vxlan_rule $local_ip $remote_ip
    cleanup
}

function do_test() {
    title $1
    eval $1 && success
}


cleanup
do_test test_config_sriov_and_clean
do_test test_add_esw_rule_only_pf0_in_switchdev
do_test test_add_esw_rule_after_multipath_was_ready_before

test_done
