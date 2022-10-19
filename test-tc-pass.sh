#!/bin/bash
#
# Test the TC pass action
#
# Use TC to offload the following to the HW DP:
# * Low priority rules forwarding all ipv4 and arp traffic between to VFs.
# * A high priority rule matching a specific src MAC address which will miss
#   to SW using the TC pass action.
#
# In SW DP, use OVS with offloads disabled with default normal rule,
# enabling forwarding all traffic on the SW DP.
#
# Send traffic not matching the specific src MAC, verifying the  pass action
# is not invoked for it, and that all traffic goes on the HW DP.
#
# Then, send traffic matching the specific src MAC, and verify that those,
# and only those, packets are processed on the SW DP.
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

br=tst1

VF1_IP="7.7.1.7"
VF1_MAC="e4:0a:05:08:00:02"
SPECIFIC_MAC="e4:0a:05:08:00:04"
VF2_IP="7.7.1.1"
VF2_MAC="e4:0a:05:08:00:03"
namespace1=ns1
namespace2=ns2
ARP_PRIO=10
IP_PRIO_LOW=1000
IP_PRIO_HIGH=999

function add_rep_tc_fwd_rules() {
    local in_rep=$1
    local out_rep=$2
    local arp_prio=$3
    local ip_prio=$4

    tc_filter add dev $in_rep ingress prio $arp_prio protocol arp flower action mirred egress mirror dev $out_rep
    tc_filter add dev $in_rep ingress prio $ip_prio protocol ip flower action mirred egress mirror dev $out_rep
}

function cleanup() {
    reset_tc $REP $REP2
    ovs_clear_bridges
    ovs_conf_set hw-offload true
    ip -all netns delete
}
trap cleanup EXIT

function setup_ovs() {
    echo "Setup ovs"
    start_clean_openvswitch
    ovs_conf_set hw-offload false
    restart_openvswitch
    ovs-vsctl add-br $br
    ovs-vsctl add-port $br $REP
    ovs-vsctl add-port $br $REP2
}

function config_local_host() {
    title "Config local host"
    ip -all netns delete
    config_sriov 2
    enable_switchdev
    unbind_vfs
    bind_vfs
    require_interfaces REP REP2 NIC VF VF2
    setup_ovs
    reset_tc $REP $REP2
    config_vf $namespace1 $VF $REP $VF1_IP $VF1_MAC
    config_vf $namespace2 $VF2 $REP2 $VF2_IP $VF2_MAC
    add_rep_tc_fwd_rules $REP $REP2 $ARP_PRIO $IP_PRIO_LOW
    add_rep_tc_fwd_rules $REP2 $REP $ARP_PRIO $IP_PRIO_LOW
}

function run() {
    local n=5

    title "Insert TC rule with pass action for specific src MAC"
    tc_filter add dev $REP ingress prio $IP_PRIO_HIGH flower src_mac $SPECIFIC_MAC action pass

    title "Test traffic from non-specific MAC is handled exclusively on the HW DP"
    echo "Sniff packets on $REP"
    timeout $n tcpdump -pqnnei $REP -c $n icmp &
    local tpid=$!
    sleep 0.5

    echo "Run ping for $((n+1)) seconds"
    ip netns exec $namespace1 ping -I $VF $VF2_IP -c $n -w $((n+1)) -q && success || err "Ping failed"
    verify_no_traffic $tpid

    title "Test traffic from specific MAC is passed to SW DP"
    ip -netns $namespace1 link set $VF address $SPECIFIC_MAC

    tdfile=/tmp/tdfile.pcap
    timeout $((n+1)) tcpdump -pqnnei $REP -c $n ip -w $tdfile &
    local tpid=$!
    sleep 0.5

    echo "Run ping for $((n+1)) seconds"
    ip netns exec $namespace1 ping -I $VF $VF2_IP -c $n -w $((n+1)) -q && success || err "Ping failed"

    wait $tpid
    npkts=`tcpdump -nne -r $tdfile | grep "$SPECIFIC_MAC" | wc -l`
    other_pkts=`tcpdump -nne -r $tdfile | grep -v "$SPECIFIC_MAC" | wc -l`

    title "Verify $n packets from $SPECIFIC_MAC captured"
    if [[ $npkts -ne $n ]]; then
        err "Expected to see $n packets from $SPECIFIC_MAC"
    fi

    if [[ $other_pkts -ne 0 ]]; then
        err "Not expected to see packets from host other than $SPECIFIC_MAC"
    fi

    rm -f $tdfile
}

config_local_host
run
cleanup
trap - EXIT
test_done
