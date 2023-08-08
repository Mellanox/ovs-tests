#!/bin/bash
#
# Test bridge offload of bonding device (LAG) in configuration with remote
# server and VFs is VLANs attached (both access and trunk modes). Test runs ping
# between VF->VF and VF->UL(LAG) changing active ports before each iteration.
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-br.sh

min_nic_cx6dx
require_remote_server
require_module bonding

br=tst1
bond=bond0

VF1_IP="7.7.1.7"
VF1_MAC="e4:0a:05:08:00:03"
VF2_IP="7.7.1.8"
VF2_MAC="e4:0a:05:08:00:05"
REMOTE_IP="7.7.1.1"
REMOTE_MAC="0c:42:a1:58:ac:28"
namespace1=ns1
namespace2=ns2
time=5

function cleanup() {
    clear_remote_bonding
    on_remote "ip a flush dev $REMOTE_NIC
               ip a flush dev $REMOTE_NIC2"

    ip link del name $br type bridge 2>/dev/null
    ip netns del $namespace1 &>/dev/null
    ip netns del $namespace2 &>/dev/null
    sleep 0.5
    unbind_vfs
    unbind_vfs $NIC2
    sleep 1
    clear_bonding
    ip a flush dev $NIC
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
config_bonding $NIC $NIC2

unbind_vfs
unbind_vfs $NIC2
bind_vfs
bind_vfs $NIC2
sleep 1
REP2=`get_rep 0 $NIC2`
VF2=`get_vf 0 $NIC2`
require_interfaces REP REP2 NIC NIC2

ovs_clear_bridges
create_bridge_with_interfaces $br $bond $REP $REP2
config_vf $namespace1 $VF $REP $VF1_IP
config_vf $namespace2 $VF2 $REP2 "127.0.0.127"
add_vf_vlan $namespace2 $VF2 $REP2 $VF2_IP 2 $VF2_MAC

title "Config remote host"
remote_disable_sriov
config_remote_bonding
on_remote "ip l set dev bond0 up
           ip link add link bond0 name bond0.2 type vlan id 2
           ip link set bond0.2 address $REMOTE_MAC
           ip address replace dev bond0.2 $REMOTE_IP/24
           ip link set bond0.2 up"

sleep 1

ip link set $br type bridge vlan_filtering 1
bridge vlan add dev $REP vid 2 pvid untagged
bridge vlan add dev $REP2 vid 2
bridge vlan add dev bond0 vid 2

slave1=$NIC
slave2=$NIC2
remote_active=$REMOTE_NIC

title "test ping esw0->esw1"
change_slaves
flush_bridge $br
verify_ping_ns $namespace1 $VF $REP $VF2_IP $time $time

title "test ping esw0->bond"
change_slaves
flush_bridge $br
verify_ping_ns $namespace1 $VF $bond $REMOTE_IP $time $time

title "test ping esw1->esw0"
change_slaves
flush_bridge $br
verify_ping_ns $namespace2 $VF2.2 $REP2 $VF1_IP $time $time

title "test ping esw1->bond"
change_slaves
flush_bridge $br
verify_ping_ns $namespace2 $VF2.2 $bond $REMOTE_IP $time $time

cleanup
trap - EXIT
test_done
