#!/bin/bash
#
# Test dp-hash with tunnel port entropy after vxlan encap
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

config_sriov 2
enable_switchdev
bind_vfs

IB_PORT=`get_port_from_pci`

function cleanup() {
    ovs_conf_remove hw-offload-ct-size
    cleanup_test
}
trap cleanup EXIT

function config() {
    ovs_conf_set hw-offload-ct-size 0
    cleanup_test
    config_tunnel "vxlan" 1 br-phy br-phy
    config_local_tunnel_ip $LOCAL_TUN_IP br-phy
    ovs-vsctl show
}

function add_openflow_rules() {
    local bridge="br-phy"
    ovs-ofctl del-flows $bridge
    ovs-ofctl add-group $bridge group_id=1,type=select,selection_method=doca,bucket=watch_port=$IB_PORT,output:$IB_PORT

    # avoid dp_hash on ip6
    ovs-ofctl add-flow $bridge in_port=$IB_PF0_PORT0,ip6,actions=drop

    ovs-ofctl add-flow $bridge in_port=$IB_PF0_PORT0,actions=vxlan_$bridge
    ovs-ofctl add-flow $bridge in_port=vxlan_$bridge,actions=$IB_PF0_PORT0

    ovs-ofctl add-flow $bridge in_port=LOCAL,actions=group:1
    ovs-ofctl add-flow $bridge in_port=$IB_PORT,actions=LOCAL

    # avoid dp_hash on arp
    local tun_mac=$(on_remote "cat /sys/class/net/$TUNNEL_DEV/address")
    ip netns exec ns0 ip n r $REMOTE_IP dev $VF lladdr $tun_mac

    debug "OVS groups:"
    ovs-ofctl dump-groups $bridge --color

    ovs_ofctl_dump_flows
}

function validate_rules() {
    local cmd="ovs-appctl dpctl/dump-flows -m type=offloaded | grep -v 'recirc_id(0)' | grep 'eth_type(0x0800)'"
    local x=$(eval $cmd | wc -l)

    if [ "$x" != "1" ]; then
        eval $cmd
        fail "Expected to have 1 flow, have $x"
    fi
}

function verify_entropy() {
    on_remote "tcpdump -r /tmp/out -n udp[$ip_pos:4]=0x01010107 | grep -o \"7.7.7.7.[0-9]\+\" | cut -d. -f5" > /tmp/ports

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

function test_icmp() {
    title "Test icmp"

    debug "Capture packets"
    on_remote "tcpdump -nnei $NIC -w /tmp/out" &
    sleep 0.5
    
    ovs_flush_rules
    debug "Send icmp packets"
    exec_dbg ip netns exec ns0 ping -q $REMOTE_IP -i 0.5 -c 10 || fail "Ping failed"
    on_remote "killall tcpdump"
    wait

    debug "Verify src port entropy"
    ip_pos=42
    verify_entropy

    validate_rules
    ovs_flush_rules
}

function run() {
    config
    config_remote_tunnel vxlan
    add_openflow_rules
    sleep 2
    test_icmp
}

run
trap - EXIT
cleanup
test_done
