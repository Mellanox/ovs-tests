#!/bin/bash
#
# 1. set legacy mode
# 2. add tc rule
# 3. change mode to switchdev
# 4. del rules
#
# Expected result: not to crash
#
# Bug SW #935342: Adding rule in legacy mode and then deleting in switchdev mode
# results in null deref
#

NIC=${1:-ens5f0}

my_dir="$(dirname "$0")"
. $my_dir/common.sh


set -e

COUNT=5
NIC1=$NIC

function add_rules() {
    title "- add some rules"
    for i in `seq $COUNT`; do
        num1=`printf "%02x" $((i / 100))`
        num2=`printf "%02x" $((i % 100))`
        tc filter add dev $NIC1 protocol ip parent ffff: \
            flower skip_sw indev $NIC1 \
            src_mac e1:22:33:44:${num1}:$num2 \
            dst_mac e2:22:33:44:${num1}:$num2 \
            action drop || fail "Failed to add rule"
    done
}

function add_vlan_rule() {
    title "- add vlan rule"
    tc filter add dev $NIC1 protocol 802.1Q parent ffff: \
                flower \
                        dst_mac e4:11:22:11:4a:51 \
                        src_mac e4:11:22:11:4a:50 \
                        vlan_ethtype 0x800 \
                        vlan_id 100 \
                        vlan_prio 0 \
                action vlan pop \
                action drop || err "Failed"
}

function add_vxlan_rule() {
    title "- add vxlan rule"
    tc filter add dev ${NIC} protocol 0x806 parent ffff: \
                flower \
                        dst_mac e4:11:22:11:4a:51 \
                        src_mac e4:11:22:11:4a:50 \
                        enc_src_ip 20.1.11.1 \
                        enc_dst_ip 20.1.12.1 \
                        enc_key_id 100 \
                        enc_dst_port 4789 \
                action tunnel_key unset \
                action mirred egress redirect dev ${REP} && success || err "Failed"
}


title "Add rule in legacy mode and reset in switchdev"
reset_tc_nic $NIC
switch_mode_legacy
add_rules
add_vlan_rule
title "- unbind vfs"
unbind_vfs
title "- switch to switchdev"
switch_mode_switchdev
title " - reset tc"
reset_tc_nic $NIC
success

title "Add rule in switchdev mode and reset in legacy"
reset_tc_nic $NIC
switch_mode_switchdev
title "- add rules"
add_rules
add_vlan_rule
add_vxlan_rule
title "- unbind vfs"
unbind_vfs
title "- switch to legacy"
switch_mode_legacy
title " - reset tc"
reset_tc_nic $NIC
success

test_done
