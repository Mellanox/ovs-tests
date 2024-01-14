#!/bin/bash
#
# Test OVS vxlan entropy
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

PCAP="/tmp/out.pcap"

require_remote_server

config_sriov 2
enable_switchdev
bind_vfs

trap cleanup_test EXIT

function config() {
    cleanup_test

    config_tunnel "vxlan"
    config_remote_tunnel "vxlan"
    config_local_tunnel_ip $LOCAL_TUN_IP br-phy
    local pf0vf0=`get_port_from_pci $PCI 0`
    ovs-ofctl add-flow br-int in_port=$pf0vf0,actions=vxlan_br-int
    ovs-ofctl dump-flows br-int --color
}

function config_push_vlan() {
    title "Config push vlan"
    local pf0vf0=`get_port_from_pci $PCI 0`
    ovs-ofctl del-flows br-int in_port=$pf0vf0
    ovs-ofctl -O OpenFlow13 add-flow br-int in_port=$pf0vf0,actions=push_vlan:0x8100,mod_vlan_vid:5,vxlan_br-int
    ovs-ofctl dump-flows br-int --color
}

function verify_entropy() {
    on_remote "tcpdump -r $PCAP -n udp[$ip_pos:4]=0x01010101 | grep -o \"7.7.7.7.[0-9]\+\" | cut -d. -f5" > /tmp/ports

    local port1=`head -1 /tmp/ports`
    local port2=`tail -1 /tmp/ports`

    if [ -z "$port1" ] || [ -z "$port2" ]; then
        err "Cannot get ports"
    elif [ "$port1" != "$port2" ]; then
        err "Expected ports to be the same. $port1 vs $port2"
    else
        debug "port $port1"
        success
    fi
}

function start_tcpdump() {
    on_remote "rm -f /tmp/*.pcap ; tcpdump -nnei $NIC -w $PCAP" &
}

function test_udp() {
    title "Test udp"

    debug "Capture packets"
    start_tcpdump

    debug "Send udp packets"
    ip netns exec ns0 python -c "from scapy.all import *; p=Ether()/IP(src='1.1.1.1')/UDP(); sendp(p, iface='$VF', count=10, inter=0.5)"
    on_remote "killall tcpdump"
    wait

    debug "Verify src port entropy"
    verify_entropy

    ovs_flush_rules
}

function test_tcp() {
    title "Test tcp"

    debug "Capture packets"
    start_tcpdump

    debug "Send tcp packets"
    ip netns exec ns0 python -c "from scapy.all import *; p=Ether()/IP(src='1.1.1.1')/TCP(); sendp(p, iface='$VF', count=10, inter=0.5)"
    on_remote "killall tcpdump"
    wait

    debug "Verify src port entropy"
    verify_entropy

    ovs_flush_rules
}

function test_icmp() {
    title "Test icmp"

    debug "Capture packets"
    start_tcpdump

    debug "Send icmp packets"
    ip netns exec ns0 python -c "from scapy.all import *; p=Ether()/IP(src='1.1.1.1')/ICMP(); sendp(p, iface='$VF', count=10, inter=0.5)"
    on_remote "killall tcpdump"
    wait

    debug "Verify src port entropy"
    verify_entropy

    ovs_flush_rules
}

function run() {
    config

    ip_pos=42
    test_udp
    test_tcp
    test_icmp

    config_push_vlan
    ip_pos=46
    test_udp
}

run
trap - EXIT
cleanup_test
test_done
