#!/bin/bash
#
# Test multiple bridge instances on single eswitch:
# - Create two bridge instances, verify that net devices attached to the same
# bridge can ping each other and that net devices from different bridges can't
# ping each other.
# - Move net device to another bridge and verify connectivity with devices on
# the same bridge instance.
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-br.sh

br1=tst1
br2=tst2

VF1_IP="7.7.1.7"
VF2_IP="7.7.1.1"
VF3_IP="7.7.1.2"
VF4_IP="7.7.1.3"
namespace1=ns1
namespace2=ns2
namespace3=ns3
namespace4=ns4
time=5

not_relevant_for_nic cx4 cx4lx cx5

function cleanup() {
    ip link del name $br1 type bridge 2>/dev/null
    ip link del name $br2 type bridge 2>/dev/null
    ip netns del $namespace1 &>/dev/null
    ip netns del $namespace2 &>/dev/null
    ip netns del $namespace3 &>/dev/null
    ip netns del $namespace4 &>/dev/null
}
trap cleanup EXIT
cleanup

title "Config local host"
config_sriov 4
enable_switchdev
REP3=`get_rep 2`
REP4=`get_rep 3`
require_interfaces REP REP2 REP3 REP4 NIC
unbind_vfs
bind_vfs
VF3=`get_vf 2`
VF4=`get_vf 3`
sleep 1

ovs_clear_bridges
create_bridge_with_interfaces $br1 $REP $REP2
create_bridge_with_interfaces $br2 $REP3 $REP4
config_vf $namespace1 $VF $REP $VF1_IP
config_vf $namespace2 $VF2 $REP2 $VF2_IP
config_vf $namespace3 $VF3 $REP3 $VF3_IP
config_vf $namespace4 $VF4 $REP4 $VF4_IP
sleep 1

title "test ping on bridges"
verify_ping_ns $namespace1 $VF $REP2 $VF2_IP $time
verify_ping_ns $namespace3 $VF3 $REP4 $VF4_IP $time
title "verify no connectivity between bridges"
ip netns exec $namespace1 ping -I $VF $VF4_IP -c 3 -w 3 -q && err "Expected to fail ping"

title "move $VF to $br2 and verify connectivity"
ip link set $REP master $br2
verify_ping_ns $namespace1 $VF $REP4 $VF4_IP $time
verify_ping_ns $namespace3 $VF3 $REP4 $VF4_IP $time
title "verify no connectivity between bridges"
ip netns exec $namespace1 ping -I $VF $VF2_IP -c 3 -w 3 -q && err "Expected to fail ping"

cleanup
trap - EXIT
test_done
