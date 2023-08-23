#!/bin/bash
#
# Test OVS-DPDK with gre traffic and modify the udp ports
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

PKTGEN_DIR=$(cd "$(dirname ${BASH_SOURCE[0]})" && pwd)
pktgen=$PKTGEN_DIR/../scapy-traffic-tester.py

trap cleanup_test EXIT

require_remote_server

gre_set_entropy

config_sriov 2
require_interfaces REP NIC
enable_switchdev
bind_vfs

cleanup_test

function config() {
    config_tunnel gre
    config_local_tunnel_ip $LOCAL_TUN_IP br-phy
    config_remote_tunnel gre
    start_vdpa_vm
}

function add_openflow_rules() {
    local bridge="br-int"
    local rep=`get_port_from_pci $PCI 0`

    debug "Adding openflow rules for bridge $bridge"
    ovs-ofctl del-flows $bridge
    ovs-ofctl add-flow $bridge "table=0,arp,actions=normal"
    ovs-ofctl add-flow $bridge "table=0,icmp,actions=normal"
    ovs-ofctl add-flow $bridge "in_port=$rep,ip,udp,tp_src=4051,actions=mod_tp_src=4050,output:gre_${bridge}"
    ovs-ofctl add-flow $bridge "in_port=gre_${bridge},ip,udp,tp_dst=4050,actions=mod_tp_dst=4051,output:$rep"
    ovs-ofctl dump-flows $bridge --color
}

function run() {
    local t=10

    add_openflow_rules

    verify_ping
    ip netns exec ns0 timeout $t $pktgen -l -i $VF --src-ip $REMOTE_IP --dst-ip $LOCAL_IP --src-port 4051 --dst-port 4051 &
    on_remote timeout $t $pktgen -i $TUNNEL_DEV --src-ip $REMOTE_IP --dst-ip $LOCAL_IP --src-port 4051 --dst-port 4050 --time $t &

    #sleep for 5 seconds for traffic to be sent
    sleep 5
    check_offload_contains 'set\(udp\(.*' 2
    check_dpdk_offloads
}

config
run
trap - EXIT
cleanup_test
test_done
