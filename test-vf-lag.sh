#!/bin/bash
#
# Basic VF LAG test
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module bonding

config_sriov 2
# TODO require vf lag support ?
reset_tc $NIC

local_ip="2.2.2.2"
remote_ip="2.2.2.3"
dst_mac="e4:1d:2d:fd:8b:02"
flag=skip_sw
dst_port=1234
id=98

function tc_filter() {
    eval2 tc filter $@ && success
}

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

function is_bonded() {
    dmesg | tail -n10 | grep -E "mlx5_core [0-9.:]+ lag map port 1:. port 2:."
    return $?
}

function config_bonding() {
    modprobe -r bonding
    modprobe bonding mode=active-backup
    ifconfig bond0 up
    ifenslave bond0 $1 $2
    if ! is_bonded ; then
        err "Driver bond failed"
    fi
    reset_tc bond0
}

function config() {
    echo "- Config"
    modprobe -r bonding &>/dev/null
    disable_sriov
    enable_sriov
    enable_switchdev $NIC
    enable_switchdev $NIC2
    reset_tc $NIC $NIC2 $REP
    config_bonding $NIC $NIC2
}

function cleanup() {
    ifenslave -d bond0 $NIC $NIC2 2>/dev/null
    modprobe -r bonding 2>/dev/null
    ifconfig $NIC down
}

function config_vxlan() {
    ip link add vxlan1 type vxlan id $id dev $NIC dstport $dst_port
    ip link set vxlan1 up
    ip addr add ${local_ip}/24 dev $NIC
    tc qdisc add dev vxlan1 ingress
    ip link set $NIC up
    ip n add $remote_ip lladdr $dst_mac dev $NIC
}

function clean_vxlan() {
    ip link del dev vxlan1 2> /dev/null
    ip n del ${remote_ip} dev $NIC 2>/dev/null
    ip n del ${remote_ip6} dev $NIC 2>/dev/null
    ip addr flush dev $NIC
}

function add_vxlan_rule() {
    local local_ip="$1"
    local remote_ip="$2"

    echo "local_ip $local_ip remote_ip $remote_ip"

    # tunnel key set
    ifconfig $NIC up
    reset_tc $REP $NIC vxlan1

    # encap
    title "- encap"
    tc_filter add dev $REP protocol arp parent ffff: prio 1 \
        flower dst_mac $dst_mac $flag \
        action tunnel_key set \
            id $id src_ip ${local_ip} dst_ip ${remote_ip} dst_port ${dst_port} \
        action mirred egress redirect dev vxlan1

    # decap
    title "- decap"
    tc_filter add dev vxlan1 protocol arp parent ffff: prio 2 \
        flower dst_mac $dst_mac \
            enc_src_ip $remote_ip \
            enc_dst_ip $local_ip \
            enc_dst_port $dst_port \
            enc_key_id $id \
        action tunnel_key unset \
            id $id src_ip ${local_ip} dst_ip ${remote_ip} dst_port ${dst_port} \
        action mirred egress redirect dev $REP

    # because of upstream issue adding decap rule in skip_sw we add with
    # policy none and verify in_hw bit.
    # Bug SW #1360599: [upstream] decap rule offload attempt with skip_sw fails
    tc filter show dev vxlan1 ingress prio 2 | grep -q -w in_hw || err "Decap rule not in hw"

    reset_tc $REP $NIC vxlan1
}

function test_add_vxlan_rule() {
    config_vxlan
    add_vxlan_rule $local_ip $remote_ip
    clean_vxlan
}

function test_add_drop_rule() {
    reset_tc bond0
    tc_filter add dev bond0 protocol arp parent ffff: prio 1 \
        flower dst_mac $dst_mac $flag \
        action drop
    reset_tc bond0
}

function test_add_redirect_rule() {
    reset_tc bond0 $REP
    title "- bond0 -> $REP"
    tc_filter add dev bond0 protocol arp parent ffff: prio 1 \
        flower dst_mac $dst_mac $flag \
        action mirred egress redirect dev $REP
    title "- $REP -> bond0"
    tc_filter add dev $REP protocol arp parent ffff: prio 1 \
        flower dst_mac $dst_mac $flag \
        action mirred egress redirect dev bond0
    reset_tc bond0 $REP
}

function do_cmd() {
    title $1
    eval $1
}


trap cleanup EXIT
cleanup
config
do_cmd test_add_drop_rule
do_cmd test_add_redirect_rule
do_cmd test_add_vxlan_rule
cleanup
#TODO: verify rule in hw in both ports.
# verify after bond we created VF LAG in FW
# verify delete bond does destroy VF LAG in FW
# TODO check create bond interface when only one port in switchdev mode
test_done
