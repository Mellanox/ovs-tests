#!/bin/bash
#
# Test bridge offloads with ping from VF in namespace to remote setup
# over UL with following configurations:
# 1. Regular traffic with VLAN filtering disabled.
# 2. Both VF and UL are pvid/untagged ports of default VLAN 1.
# 3. Both VF and UL are tagged with VLAN 2.
# 4. VF is tagged with VLAN 3, UL is pvid/untagged with VLAN 3.
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-br.sh

br=tst1
REMOTE_SERVER=${REMOTE_SERVER:-$1}
REMOTE_NIC=${REMOTE_NIC:-$2}

LOCAL_IP="7.7.1.7"
LOCAL_MAC="e4:0a:05:08:00:02"
LOCAL_IP_VLAN2="7.7.2.7"
LOCAL_MAC_VLAN2="e4:0a:05:08:00:03"
LOCAL_IP_VLAN3="7.7.3.7"
LOCAL_MAC_VLAN3="e4:0a:05:08:00:04"
REMOTE_IP="7.7.1.1"
REMOTE_MAC="0c:42:a1:58:ac:28"
REMOTE_IP_VLAN2="7.7.2.1"
REMOTE_MAC_VLAN2="0c:42:a1:58:ac:29"
REMOTE_IP_UNTAGGED="7.7.3.1"
namespace1=ns1
time=5

require_remote_server
not_relevant_for_nic cx4 cx4lx cx5 cx6 cx6lx

function cleanup() {

    ip link del name $br type bridge 2>/dev/null
    ip netns del $namespace1 &>/dev/null

    on_remote "\
        ip link del link $REMOTE_NIC name ${REMOTE_NIC}.2 type vlan id 2 &>/dev/null;\
        ip a del $REMOTE_IP/24 dev $REMOTE_NIC &>/dev/null;\
        ip a del $REMOTE_IP_UNTAGGED/24 dev $REMOTE_NIC &>/dev/null"
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
create_bridge_with_interfaces $br $NIC $REP
config_vf $namespace1 $VF $REP $LOCAL_IP $LOCAL_MAC
add_vf_vlan $namespace1 $VF $REP $LOCAL_IP_VLAN2 2 $LOCAL_MAC_VLAN2
add_vf_vlan $namespace1 $VF $REP $LOCAL_IP_VLAN3 3 $LOCAL_MAC_VLAN3

ip addr flush dev $NIC
ip link set dev $NIC up

title "Config remote host"
remote_disable_sriov
on_remote "\
        ip link set $REMOTE_NIC address $REMOTE_MAC;\
        ip a add dev $REMOTE_NIC $REMOTE_IP/24;\
        ip link add link $REMOTE_NIC name ${REMOTE_NIC}.2 type vlan id 2;\
        ip link set ${REMOTE_NIC}.2 address $REMOTE_MAC_VLAN2;\
        ip address replace dev ${REMOTE_NIC}.2 $REMOTE_IP_VLAN2/24;\
        ip a add dev $REMOTE_NIC $REMOTE_IP_UNTAGGED/24;\
        ip link set $REMOTE_NIC up;\
        ip link set ${REMOTE_NIC}.2 up"

sleep 1

title "test ping (no VLAN)"
verify_ping_ns $namespace1 $VF $NIC $REMOTE_IP $time

ip link set tst1 type bridge vlan_filtering 1

title "test ping (VLAN untagged<->untagged)"
flush_bridge $br
sleep 1
verify_ping_ns $namespace1 $VF $NIC $REMOTE_IP $time

title "test ping (VLAN tagged<->tagged)"
flush_bridge $br
bridge vlan add dev $REP vid 2
bridge vlan add dev $NIC vid 2
sleep 1
verify_ping_ns $namespace1 $VF.2 $NIC $REMOTE_IP_VLAN2 $time

title "test ping (VLAN tagged<->untagged)"
flush_bridge $br
bridge vlan add dev $REP vid 3
bridge vlan add dev $NIC vid 3 pvid untagged
sleep 1
verify_ping_ns $namespace1 $VF.3 $NIC $REMOTE_IP_UNTAGGED $time

cleanup
trap - EXIT
test_done
