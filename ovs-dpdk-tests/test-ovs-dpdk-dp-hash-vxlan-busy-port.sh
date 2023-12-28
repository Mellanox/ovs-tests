#!/bin/bash
#
# Test dp-hash after vxlan encap, busy port issue
#
# [DAL2OVS] Bug SW #3676502: After sr-iov deletion/recreation, Ping started failing from x86 host to connected svi(configured on vf interface).
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
    ovs_conf_remove max-idle
    cleanup_test
    # reconfiguring sriov while port in dpdk seems the driver doesn't create the representor.
    # reconfig sriov after ovs is cleared.
    config_sriov 0
    config_sriov 2
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
    ovs-ofctl add-group $bridge group_id=1,type=select,bucket=watch_port=$IB_PORT,output:$IB_PORT

    ovs-ofctl add-flow $bridge in_port=$IB_PF0_PORT0,actions=vxlan_$bridge
    ovs-ofctl add-flow $bridge in_port=vxlan_$bridge,actions=$IB_PF0_PORT0

    ovs-ofctl add-flow $bridge in_port=LOCAL,actions=group:1
    ovs-ofctl add-flow $bridge in_port=$IB_PORT,actions=LOCAL

    debug "OVS groups:"
    ovs-ofctl dump-groups $bridge --color

    ovs_ofctl_dump_flows
}

function run() {
    config
    config_remote_tunnel vxlan
    add_openflow_rules
    sleep 2
    ovs_conf_set max-idle 300000
    verify_ping $REMOTE_IP ns0
    ovs-appctl dpctl/dump-flows -m

    config_sriov 0
    local i
    for i in `seq 8`; do
        ovs-vsctl show | grep -q error && break
        sleep 1
    done
    if [ $i -gt 7 ]; then
        err "Expected a port error"
    fi
    ovs-vsctl show
    ovs-vsctl show | grep -q "already in use" && err "Failed to clean some ports."
    # e.g.: error: "'pf0vf0' is trying to use device '0000:08:00.0,representor=[0],dv_xmeta_en=4,dv_flow_en=2' which is already in use by 'pf0vf0'"

    # issue could be on reconfigure.
    config_sriov 2
    sleep $i
    ovs-vsctl show
    ovs-vsctl show | grep -q "already in use" && err "Failed to clean some ports."
}

run
trap - EXIT
cleanup
test_done
