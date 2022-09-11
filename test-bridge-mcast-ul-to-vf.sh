#!/bin/bash
#
# Test bridge offloads with multicast ping from remote setup to three VFs in
# namespaces with following configurations:
#
# 1. Simple bridge with UL and VFs attached with VLAN filtering disabled.
#
# 2. Bridge with UL in access mode and VFs mixed (some trunk, some access mode)
# on vid 2 with VLAN filtering enabled.
#
# 3. Bridge with UL in access mode and VFs mixed (some trunk, some access mode)
# on vid 2 with VLAN filtering enabled and VLAN tag set to 802.1ad.
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-br.sh
. $my_dir/common-br-helpers.sh

br=tst1

VF1_IP="7.7.1.7"
VF1_MAC="e4:0a:05:08:00:02"
VF1_IP_VLAN2="7.7.2.7"
VF2_IP="7.7.1.8"
VF2_MAC="e4:0a:05:08:00:05"
VF2_IP_VLAN2="7.7.2.8"
VF2_MAC_VLAN2="e4:0a:05:08:00:05"
VF2_IP_UNTAGGED="7.7.3.8"
VF3_IP="7.7.1.9"
VF3_MAC="e4:0a:05:08:00:06"
VF3_IP_VLAN2="7.7.2.9"
REMOTE_IP="7.7.1.1"
REMOTE_MAC="0c:42:a1:58:ac:28"
REMOTE_IP_VLAN2="7.7.2.1"
REMOTE_MAC_VLAN2="0c:42:a1:58:ac:29"
MCAST_IP="224.10.10.10"
namespace1=ns1
namespace2=ns2
namespace3=ns3
time=5

require_remote_server
not_relevant_for_nic cx4 cx4lx cx5 cx6 cx6lx

function cleanup() {
    ip link del name $br type bridge 2>/dev/null
    ip netns del $namespace1 &>/dev/null
    ip netns del $namespace2 &>/dev/null
    ip netns del $namespace3 &>/dev/null

    on_remote "ip a flush dev $REMOTE_NIC &>/dev/null"
}
trap cleanup EXIT
cleanup

title "Config local host"
config_sriov 4
enable_switchdev
REP3=`get_rep 2`
require_interfaces REP REP2 REP3 NIC
unbind_vfs
bind_vfs
VF3=`get_vf 2`
sleep 1

ovs_clear_bridges
remote_disable_sriov
sleep 1


title "test ping (no VLAN)"
test_remote_no_vlan_mcast

title "test ping (VLAN tagged<->mixed)"
test_remote_trunk_to_mixed_vlan_mcast

title "test ping (QinQ tagged<->mixed)"
test_remote_trunk_to_mixed_qinq_mcast

cleanup
trap - EXIT
test_done
