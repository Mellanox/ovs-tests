#!/bin/bash
#
# Test multicast/broadcast traffic offload over hairpin in NIC mode.
# Topology: in local setup, both PFs are attached to same OVS bridge (hairpin).
#           in remote setup, both PFs are attached to separated NS configured with an IP.
# Traffic: case 1 -> sending ARP ping (broadcast)from PF0 -> PF1.
#          case 2 -> Sending ICMP6 (multicast) from PF1 -> PF0.
#
# [MLNX OFED] Bug SW #3047142: OvS / TC Flower HW offload has an issue with ARP in NIC mode (non SR-IOV)
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_remote_server

IP="7.7.7.1"
IP2="7.7.7.2"
NS=p0ns
NS2=p1ns

function remote_cleanup() {
    on_remote_exec " ip netns del $NS &>/dev/null
                     ip netns del $NS2 &>/dev/null
                     config_sriov 2 $NIC
                     enable_switchdev
                   " &>/dev/null
}

function cleanup() {
   ovs_clear_bridges
   config_sriov 2 $NIC
   enable_switchdev
   remote_cleanup
}
trap cleanup EXIT

function config_ovs() {
    title "Config OvS and create hairpin"
    start_clean_openvswitch
    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $NIC
    ovs-vsctl add-port br-ovs $NIC2
    ovs-vsctl show
}

function config() {
    title "Config local"
    disable_sriov
    config_ovs
    ifconfig $NIC up
    ifconfig $NIC2 up
}

function config_remote() {
    title "Config remote"
    remote_disable_sriov
    on_remote " ip netns add $NS
                ip link set dev $NIC netns $NS
                ip netns exec $NS ifconfig $NIC $IP/24 up
                ip netns add $NS2
                ip link set dev $NIC2 netns $NS2
                ip netns exec $NS2 ifconfig $NIC2 $IP2/24 up
              "
}

function check_offloaded_rules() {
    local eth_type=$1
    local in_port=$2
    local out_port=$3

    title "Checking offload"
    ovs_dump_flows -m | grep -q "in_port($in_port),.*eth_type($eth_type),.*offloaded:yes,.*actions:$out_port"

    if [ $? -ne 0 ]; then
        err "Failed to offload"
    else
        success
    fi
}

function run_traffic() {
    local t=3

    title "Sending ARP ping from $IP to $IP2"
    on_remote ip netns exec $NS arping $IP2 -c $t

    if [ $? -ne 0 ]; then
        err "Arp ping failed"
    fi

    check_offloaded_rules 0x0806 $NIC $NIC2

    title "Sending IPv6 ping to $ipv6 from $NIC2"
    local ipv6=`on_remote ip netns exec $NS ifconfig $NIC | grep inet6 | awk -F' ' '{print $2}' | awk '{print $1}'`
    on_remote ip netns exec $NS2 ping6 $ipv6%$NIC2 -c $t

    if [ $? -ne 0 ]; then
        err "IPv6 ping failed"
    fi

    check_offloaded_rules 0x86dd $NIC2 $NIC
}

config
config_remote
run_traffic
cleanup
trap - EXIT
test_done
