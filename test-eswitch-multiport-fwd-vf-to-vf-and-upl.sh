#! /bin/bash

# Verify that we can add rule to a VF representor that forwards to both uplink and other VF
# 3107213: [Upstream][Multiport] Sanity traffic is not passing with syndrome 0x7bc3c1 and errors in dmesg

my_dir="$(dirname "$0")"
. $my_dir/common.sh

min_nic_cx6dx

function cleanup() {
    local_cleanup
}

trap cleanup EXIT

function run_test() {
    enable_lag_resource_allocation_mode
    set_lag_port_select_mode "multiport_esw"
    config_sriov 2
    config_sriov 2 $NIC2
    enable_switchdev
    enable_switchdev $NIC2
    enable_esw_multiport
    reset_tc $REP $NIC $NIC2
    ip link set up dev $NIC
    ip link set up dev $NIC2
    ip link set up dev $REP
    ip link set up dev $REP2
    tc_filter add dev $REP prot all ingress flower skip_sw action mirred egress redirect dev $NIC action mirred egress redirect dev $REP2
}

function local_cleanup() {
    reset_tc $NIC $NIC2 $REP
    disable_esw_multiport
    restore_lag_port_select_mode
    restore_lag_resource_allocation_mode
    enable_legacy $NIC2
    config_sriov 0 $NIC2
}

run_test
cleanup
trap - EXIT
test_done
