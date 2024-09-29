#!/bin/bash
#
# Test OVS-DOCA/DPDK unexpected stats jump upon modify flow
#
# [OVS] Bug SW #4094117: [DAL2OVS] unexpected jump in group stats packet count
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

config_sriov 2
enable_switchdev
bind_vfs

trap cleanup EXIT

function cleanup() {
    ovs_conf_remove max-idle
    cleanup_test
}

function config() {
    cleanup_test
    config_simple_bridge_with_rep 2
    config_ns ns0 $VF $LOCAL_IP
    config_ns ns1 $VF2 $REMOTE_IP
}

function add_openflow_rules() {
    debug "adding openflow rules"
    exec_dbg "ovs-ofctl add-flow br-phy \"in_port=$IB_PF0_PORT0,actions=$IB_PF0_PORT1\""
    ovs-ofctl dump-flows br-phy --color
}

function update_openflow_rules() {
    local pci=`get_pf_pci`
    local pf_port=`get_port_from_pci $pci`

    debug "updating openflow rules"
    exec_dbg "ovs-ofctl add-flow br-phy \"in_port=$IB_PF0_PORT0,actions=$pf_port\""
    ovs-ofctl dump-flows br-phy --color
}

function run() {
    config
    add_openflow_rules
    ovs_conf_set max-idle 60000

    verify_ping $REMOTE_IP ns0 56 1000 0.01 20
    update_openflow_rules
    sleep 0.5

    local x=`cat $ovs_log_path | grep "Unexpected jump in packet stats from"`
    if [[ -n "$x" ]]; then
        err "Found error in log $x"
        return
    fi
    local dp_hits=`ovs-appctl dpctl/dump-flows -m | grep icmp | grep in_port\($IB_PF0_PORT0\) | grep -v icmpv6 | grep -oP 'packets:\K\d+'`
    if [ $dp_hits -lt 900 ]; then
        err "Found $dp_hits dp-flow hits, expected at least 900"
        return
    else
        success "Found $dp_hits dp-flow hits"
    fi
    local of_hits=`ovs-ofctl dump-flows br-phy --names | grep $IB_PF0_PORT0 | grep -oP 'n_packets=\K\d+'`
    if [ $of_hits -gt 90 ]; then
        err "Found $of_hits of-flows hits, expected at most 90"
        return
    else
        success "Found $of_hits of-flows hits"
    fi

}

run
trap - EXIT
cleanup
test_done
