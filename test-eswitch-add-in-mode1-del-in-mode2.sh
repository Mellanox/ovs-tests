#!/bin/bash
#
# 1. set legacy mode
# 2. add tc rule
# 3. change mode to switchdev
# 4. del rules
#
# Expected result: not to crash
#
# Bug SW #935342: Adding rule in legacy mode and then deleting in switchdev mode results in null deref
# Bug SW #1481378: [upstream] possible circular locking dependency detected
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

COUNT=5

function add_rules() {
    title "- add some rules"
    for i in `seq $COUNT`; do
        num1=`printf "%02x" $((i / 100))`
        num2=`printf "%02x" $((i % 100))`
        tc_filter add dev $NIC protocol ip parent ffff: prio $i \
            flower skip_sw \
            src_mac e4:11:33:44:${num1}:$num2 \
            dst_mac e4:12:33:44:${num1}:$num2 \
            action drop
    done
}

function add_vlan_rule() {
    title "- add vlan rule"
    tc_filter add dev $NIC protocol 802.1Q parent ffff: prio 15 \
                flower skip_sw \
                        dst_mac e4:11:22:11:4a:51 \
                        src_mac e4:11:22:11:4a:50 \
                        vlan_ethtype 0x800 \
                        vlan_id 100 \
                        vlan_prio 0 \
                action drop
}

vx=vxlan1
ip_src=20.1.11.1
ip_dst=20.1.12.1

function create_vxlan_interface() {
    # note: we support adding decap to vxlan interface only.
    vxlan_port=4789
    ip link del $vx >/dev/null 2>&1
    ip link add $vx type vxlan dstport $vxlan_port external
    [ $? -ne 0 ] && err "Failed to create vxlan interface" && return 1
    ip link set dev $vx up
    tc qdisc add dev $vx ingress
    ip addr flush dev $NIC
    ip addr add $ip_src/16 dev $NIC
    ip neigh add $ip_dst lladdr e4:11:22:11:55:55 dev $NIC
    # wait for vxlan port to be marked as offloaded port by the hw
    sleep 1
}

function clean_vxlan_interface() {
    ip addr flush dev $NIC
    ip link del $vx
}

function add_vxlan_rule() {
    title "- add vxlan rule"
    create_vxlan_interface || return 1
    tc_filter add dev $vx protocol 0x806 parent ffff: prio 16 \
                flower \
                        dst_mac e4:11:22:11:4a:51 \
                        src_mac e4:11:22:11:4a:50 \
                        enc_src_ip $ip_dst \
                        enc_dst_ip $ip_src \
                        enc_key_id 100 \
                        enc_dst_port 4789 \
                action tunnel_key unset \
                action mirred egress redirect dev ${REP}
    # because of upstream issue adding decap rule in skip_sw we add with
    # policy none and verify in_hw bit.
    # Bug SW #1360599: [upstream] decap rule offload attempt with skip_sw fails
    tc filter show dev $vx ingress prio 16 | grep -q -w in_hw || err "Decap rule not in hw"
    clean_vxlan_interface
}

function test_legacy_switchdev() {
    title "Add rule in legacy mode and reset in switchdev"
    unbind_vfs
    switch_mode_legacy
    reset_tc $NIC
    add_rules
    add_vlan_rule
    title "- unbind vfs"
    unbind_vfs
    title "- switch to switchdev"
    __ignore_errors=1
    switch_mode_switchdev
    __ignore_errors=0
    reset_tc $NIC
    success
}

function test_switchdev_legacy() {
    title "Add rule in switchdev mode and reset in legacy"
    unbind_vfs
    switch_mode_switchdev
    reset_tc $NIC
    title "- add rules"
    add_rules
    add_vlan_rule
    add_vxlan_rule
    title "- unbind vfs"
    unbind_vfs
    title "- switch to legacy"
    __ignore_errors=1
    switch_mode_legacy
    __ignore_errors=0
    reset_tc $NIC
    success
}

config_sriov 2 $NIC
test_legacy_switchdev
sleep 2
test_switchdev_legacy
test_done
