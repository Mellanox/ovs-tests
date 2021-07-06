#!/bin/bash
#
# Test bridge offloads with ping between two VFs in separate namespaces with
# following configurations:
# 1. Regular traffic with VLAN filtering disabled.
# 2. Both VFs are pvid/untagged ports of default VLAN 1.
# 3. Both VFs are tagged with VLAN 2.
# 4. First VF is tagged with VLAN 3, second VF is pvid/untagged with VLAN 3.
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-br.sh

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
VF2_MAC_VLAN2="e4:0a:05:08:00:06"
VF2_IP_UNTAGGED="7.7.3.1"
namespace1=ns1
namespace2=ns2
time=5

not_relevant_for_nic cx4 cx4lx cx5

function cleanup() {
    ip link del name $br type bridge 2>/dev/null
    ip netns del $namespace1 &>/dev/null
    ip netns del $namespace2 &>/dev/null
}
trap cleanup EXIT
cleanup

title "Config local host"
config_sriov 2
enable_switchdev
require_interfaces REP REP2 NIC
unbind_vfs
bind_vfs
sleep 1

ovs_clear_bridges
create_bridge_with_interfaces $br $NIC $REP $REP2
config_vf $namespace1 $VF $REP $VF1_IP $VF1_MAC
add_vf_vlan $namespace1 $VF $REP $VF1_IP_VLAN2 2 $VF1_MAC_VLAN2
add_vf_vlan $namespace1 $VF $REP $VF1_IP_VLAN3 3 $VF1_MAC_VLAN3
config_vf $namespace2 $VF2 $REP2 $VF2_IP $VF2_MAC
add_vf_vlan $namespace2 $VF2 $REP2 $VF2_IP_VLAN2 2 $VF2_MAC_VLAN2

ip -netns $namespace2 address add dev $VF2 $VF2_IP_UNTAGGED/24
ip -netns $namespace2 link set $VF2 up

sleep 1

title "test ping (no VLAN)"
verify_ping_ns $namespace1 $VF $REP2 $VF2_IP $time

ip link set tst1 type bridge vlan_filtering 1

title "test ping (VLAN untagged<->untagged)"
flush_bridge $br
sleep 1
verify_ping_ns $namespace1 $VF $REP2 $VF2_IP $time

title "test ping (VLAN tagged<->tagged)"
flush_bridge $br
bridge vlan add dev $REP vid 2
bridge vlan add dev $REP2 vid 2
sleep 1
verify_ping_ns $namespace1 $VF.2 $REP2 $VF2_IP_VLAN2 $time

title "test ping (VLAN tagged<->untagged)"
flush_bridge $br
bridge vlan add dev $REP vid 3
bridge vlan add dev $REP2 vid 3 pvid untagged
sleep 1
verify_ping_ns $namespace1 $VF.3 $REP2 $VF2_IP_UNTAGGED $time

cleanup
trap - EXIT
test_done
