#!/bin/bash
#
# Test bridge static FDB entries offload. Send ping between VFs attached to a
# bridge and verify that no packets are caught on representor with tcpdump, as
# opposed to regular dynamic FDB entries that are created as a result of first
# packet passed through Linux software bridge.
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-br.sh

min_nic_cx6dx

br=tst1
VF1_IP="7.7.1.7"
VF1_MAC="e4:0a:05:08:00:02"
VF2_IP="7.7.1.1"
VF2_MAC="e4:0a:05:08:00:03"
namespace1=ns1
namespace2=ns2
time=10

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
bridge fdb replace $VF1_MAC dev $REP master static
config_vf $namespace2 $VF2 $REP2 $VF2_IP $VF2_MAC
bridge fdb replace $VF2_MAC dev $REP2 master static
sleep 1

title "test ping with static MAC addresses"
verify_ping_ns $namespace1 $VF $REP2 $VF2_IP $time 1

cleanup
trap - EXIT
test_done
