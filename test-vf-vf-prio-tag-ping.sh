#!/bin/bash
#
# Task #1695132: Upstream 5.2: VLAN pop/push (VGT+, for VZ)
# Move to prio-tag mode and ping between VFs with untagged traffic.
# The prio-tag mode would set prio tag so OVS receives tagged packets and pop.
# The rules are for VLAN rewrite (VID=0) instead of pop, so the rules are offloaded.
#
# IGNORE_FROM_TEST_ALL

my_dir="$(dirname "$0")"
. $my_dir/common.sh
require_mlxconfig

test -z "$VF2" && fail "Missing VF2"
test -z "$REP2" && fail "Missing REP2"

IP1="7.7.7.1"
IP2="7.7.7.2"

function cleanup() {
    ip netns del ns0 2> /dev/null
    ip netns del ns1 2> /dev/null
    sleep 0.5 # wait for VF to bind back
    for i in $REP $REP2 $VF $VF2 ; do
        ip link set $i mtu 1500 &>/dev/null
        ifconfig $i 0 &>/dev/null
    done
}

function set_prio_tag_mode() {
    local mode=$1
    fw_config PRIO_TAG_REQUIRED_EN=$mode
}

trap cleanup EXIT

cleanup
config_sriov 2
enable_switchdev_if_no_rep $REP
unbind_vfs
bind_vfs

require_interfaces VF VF2 REP REP2

set_prio_tag_mode 1 || fail "Cannot set prio tag mode"
fw_reset

cleanup
config_sriov 2
enable_switchdev_if_no_rep $REP
unbind_vfs
bind_vfs

start_clean_openvswitch
start_check_syndrome
config_vf ns0 $VF $REP $IP1
config_vf ns1 $VF2 $REP2 $IP2
BR=ov1
ovs-vsctl add-br $BR
ovs-vsctl add-port $BR $REP
ovs-vsctl add-port $BR $REP2

title "Test ping $VF($IP1) -> $VF2($IP2)"
ip netns exec ns0 ping -q -c 10 -i 0.2 -w 4 $IP2 && success || err

# verify the rules are offloaded, and there are prio tags that are being removed by OVS
count=`ovs_dump_tc_flows | grep ipv4 | grep "eth_type(0x8100),vlan(vid=0" | grep pop_vlan | wc -l`
if [ "$count" -ne "2" ]; then
    ovs_dump_tc_flows --names | grep ipv4
    err "No prio tag offloaded rules"
fi

del_all_bridges
cleanup
check_syndrome
set_prio_tag_mode 0
fw_reset
config_sriov 2
test_done
