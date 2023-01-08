#!/bin/bash
#
# Test bridge offloads with ping between two VFs from different eswitch
# instances with following configurations:
# 1. Regular traffic with VLAN filtering disabled.
# 2. Both VFs are pvid/untagged ports of default VLAN 1.
# 3. Both VFs are tagged with VLAN 2.
# 4. First VF is tagged with VLAN 3, second VF is pvid/untagged with VLAN 3.
# 5. First VF is pvid/untagged with VLAN 2, second VF is tagged with VLAN 2.
#
# Bug SW #2753854: [mlx5, ETH, x86] Traffic lose between 2 VFs with vlans on bridge
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-br.sh
. $my_dir/common-br-helpers.sh

min_nic_cx6dx

br=tst1
VF1_IP="7.7.1.7"
VF1_MAC="e4:0a:05:08:00:02"
VF1_IP_VLAN2="7.7.2.7"
VF1_MAC_VLAN2="e4:0a:05:08:00:03"
VF1_IP_VLAN3="7.7.3.7"
VF1_MAC_VLAN3="e4:0a:05:08:00:04"
VF2_IP="7.7.1.1"
VF2_MAC="e4:0a:05:08:00:05"
VF2_IP_VLAN2="7.7.2.1"
VF2_MAC_VLAN2="e4:0a:05:08:00:05"
VF2_IP_UNTAGGED="7.7.3.1"
namespace1=ns1
namespace2=ns2
time=5

function cleanup() {
    ip link del name $br type bridge 2>/dev/null
    ip netns del $namespace1 &>/dev/null
    ip netns del $namespace2 &>/dev/null
    config_sriov 0 $NIC2
    enable_legacy $NIC2
}
trap cleanup EXIT
cleanup

title "Config local host"
config_sriov 2
enable_switchdev
config_sriov 2 $NIC2
enable_switchdev $NIC2
require_interfaces REP REP2 NIC NIC2
unbind_vfs
unbind_vfs $NIC2
bind_vfs
bind_vfs $NIC2
sleep 1
REP2=`get_rep 0 $NIC2`
VF2=`get_vf 0 $NIC2`
ovs_clear_bridges
sleep 1

test_vf_to_vf_vlan

cleanup
trap - EXIT
test_done
