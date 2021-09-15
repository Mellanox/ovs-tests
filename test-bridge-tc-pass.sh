#!/bin/bash
#
# Test bridge spoof check implemented with two TC rules (gact pass + gact drop):
# verify that ping (VF-to-VF) passes from allowed source MAC address and fails
# from another (spoofed) address.
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-br.sh

br=tst1

VF1_IP="7.7.1.7"
VF1_MAC="e4:0a:05:08:00:02"
SPOOFED_MAC="e4:0a:05:08:00:04"
VF2_IP="7.7.1.1"
VF2_MAC="e4:0a:05:08:00:03"
namespace1=ns1
namespace2=ns2
time=5

not_relevant_for_nic cx4 cx4lx cx5 cx6 cx6lx

function cleanup() {
    reset_tc $REP
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
reset_tc $REP
create_bridge_with_interfaces $br $REP $REP2
# Don't age out rules after first ping to ensure that after installing TC rule
# packets are dropped in HW
ip link set name $br type bridge ageing_time 10000
config_vf $namespace1 $VF $REP $VF1_IP $VF1_MAC
config_vf $namespace2 $VF2 $REP2 $VF2_IP $VF2_MAC
sleep 1

title "test ping from VF MAC address"
verify_ping_ns $namespace1 $VF $REP $VF2_IP $time

title "insert TC rules for spoof check"
tc_filter add dev $REP ingress prio 1 flower src_mac $VF1_MAC action gact pass
tc_filter add dev $REP ingress prio 2 flower action gact drop

title "test ping from VF MAC address with TC rules"
verify_ping_ns $namespace1 $VF $REP $VF2_IP $time

title "test ping from spoofed MAC address with TC rules"
ip -netns $namespace1 link set $VF address $SPOOFED_MAC
ip netns exec $namespace1 ping -I $VF $VF2_IP -c 5 -w 5 -q && err "Expected to fail ping"
ip -netns $namespace1 link set $VF address $VF1_MAC

title "test ping from VF MAC address with TC rules again"
verify_ping_ns $namespace1 $VF $REP $VF2_IP $time

cleanup
trap - EXIT
test_done
