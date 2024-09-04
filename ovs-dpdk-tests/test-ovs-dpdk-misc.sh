#!/bin/bash
#
# Test some ovs function not used by default for coverage.
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

enable_switchdev
start_clean_openvswitch
ovs_add_bridge

function misc_functions() {
    local cmd
    # short commands
    for cmd in \
        "ovs-vswitchd -h" \
        "ovs-dpctl -h" \
        "ovs-vsctl -h" \
        "ovs-ofctl -h" \
        "ovs-appctl -h" \
        "ovs-appctl doca/log-get" \
        "ovs-appctl doca/log-set error" \
        "ovs-vsctl set Open_vSwitch . other_config:dpdk-offload-trace=true" \
        "ovs-appctl dpdk/dump-offloads" \
        "ovs-vsctl set Open_vSwitch . other_config:dpdk-offload-trace=false" \
        "ovs-appctl doca/log-set debug" \
        "ovs-appctl dpdk/log-set pmd:debug" \
        "ovs-appctl dpdk/log-set pmd:info" \
        "ovs-appctl dpdk/get-mempool-stats" \
        "ovs-appctl dpdk/get-memzone-stats" \
        "ovs-appctl upcall/show" \
        "ovs-vsctl set Open_vSwitch . other_config:enable-statistics=true" \
        "ovs-vsctl remove Open_vSwitch . other_config enable-statistics" \
        "ovs-appctl qos/show-types br-phy" \
        "ovs-appctl qos/show br-phy" \
        "ovs-appctl dpctl/show" \
        "ovs-appctl dpif/show" \
        "ovs-appctl dpif/dump-flows br-phy" \
        "ovs-appctl dpif/dump-flows sort=recirc br-phy" \
        "ovs-appctl dpctl/offload-stats-clear" \
        "ovs-appctl dpif-netdev/dump-packets on" \
        "ovs-appctl dpif-netdev/dump-packets off" \
        ; do
        title "Command: $cmd"
        $cmd || err "Failed cmd: $cmd"
    done

    add_expected_error_msg "EAL: failed to parse device"
    # Commands that will fail but we don't care. just increase function coverage.
    for cmd in \
        "ovs-appctl netdev-dpdk/detach x" \
        ; do
        title "Command: $cmd"
        $cmd &>/dev/null
    done
}

misc_functions
ovs_clear_bridges
test_done
