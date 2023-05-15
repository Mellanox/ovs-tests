#!/bin/bash
#
# Test interoperability of net namesapces and SRIOV/swtichdev mode
#
# The test cases are mainly to verify the rules:
# 1. A device can be moved to a network namespace and have its reps
#    created there when it is moved to switchdev mode.
# 2. A device in switchdev mode can be reloaded into a netns and
#    remain in switchdev mode, with its reps getting recreated inside the netns.
# 3. PF/uplink REP can be moved in/out of a network namespace if
#    eswitch is not in switchdev mode
# 4. Uplink REP can not be moved to another network namespace if
#    eswitch is in switchdev mode
# 5. Representors are not lost/leaked if they were in a network
#    namespace that is deleted, instead, they are evacuated to the
#    root namespace. Verify no resources are leaked in such a case,
#    ensuring afterwards that switchdev mode and SRIOV can be
#    disabled, and that the driver can be reloaded.
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

function cleanup() {
    enable_legacy
    config_sriov 0
    ip netns del ns0 &>/dev/null
    sleep 1
}

function exec_pf_in_ns0() {
    local outp=`PF_IN_NS=ns0 $@`
    echo "$outp"
}

function exec_in_ns0() {
    ip netns exec ns0 $@
}

function device_restore_root_ns() {
    exec_in_ns0 devlink dev reload pci/$PCI netns 1
}

trap cleanup EXIT

function run() {
    cleanup
    title "Verify a device can be moved to a network namespace and have its reps created there when it is moved to switchdev mode."
    ip netns add ns0
    devlink dev reload pci/$PCI netns ns0
    exec_pf_in_ns0 enable_switchdev
    exec_pf_in_ns0 config_sriov 2

    local num_devs=`PF_IN_NS=ns0 get_reps_count eth0`
    device_restore_root_ns
    cleanup
    if [ "$num_devs" != 3 ]; then
        fail "Got $num_devs reps, expect 3"
    fi

    title "Verify a device in switchdev with SRIOV enabled mode which is moved via devlink reload into a ns.
    Eswitch mode and sriov should persist in the namespace following the reload."
    enable_switchdev
    config_sriov 2
    local num_devs=`get_reps_count $NIC`
    if [ "$num_devs" == 0 ]; then
        fail "Got 0 reps"
    fi
    unbind_vfs
    ip netns add ns0
    devlink dev reload pci/$PCI netns ns0
    local esw_mode=`exec_in_ns0 devlink dev eswitch show pci/$PCI | grep "mode" | cut -d' ' -f 3`
    if [ "$esw_mode" != "switchdev" ]; then
        device_restore_root_ns
        fail "Device($PCI) eswitch mode is $esw_mode(expected to be switchdev)"
    fi
    local sriov_num=`exec_in_ns0 cat /sys/bus/pci/devices/$PCI/sriov_numvfs`
    if [ "$sriov_num" -ne 2 ]; then
        device_restore_root_ns
        fail "SRIOV number of device($PCI) is $sriov_num(expected to be 2)"
    fi
    local num_devs_in_ns=`PF_IN_NS=ns0 get_reps_count eth0`
    if [ "$num_devs_in_ns" -ne $num_devs ]; then
        device_restore_root_ns
        fail "Got $num_devs_in_ns reps in ns0, expect $num_devs"
    fi
    device_restore_root_ns
    config_sriov 0
    ip netns del ns0 &>/dev/null

    title "Verify uplink rep $NIC cannot be added to ns if in switchdev mode."
    enable_switchdev
    ip netns add ns0
    ip l set dev $NIC netns ns0 && err "Expected to fail adding $NIC to ns0."
    cleanup

    title "Verify PF $NIC can be moved among network namespaces if sriov is enabled and in legacy mode."
    ip netns add ns0
    enable_legacy
    config_sriov 2
    ip l set dev $NIC netns ns0 2>/dev/null || err "Failed to add $NIC to ns0."
    title "Verify a device cannot be switched to switchdev mode (when the devlink ns and the netdev ns do not match)."
    devlink dev eswitch set pci/$PCI mode switchdev && err "Expected to fail changing $PCI to switchdev mode."
    exec_in_ns0 devlink dev eswitch set pci/$PCI mode switchdev && err "Expected to fail changing $PCI in ns0 to switchdev mode."
    cleanup

    title "Verify VF reps would be created inside network namespace that uplink rep is in."
    ip netns add ns0
    devlink dev reload pci/$PCI netns ns0
    exec_pf_in_ns0 enable_switchdev
    exec_pf_in_ns0 config_sriov 2
    declare -A role_map=( ["eth0"]="Uplink rep" ["eth1"]="VF rep0" ["eth2"]="VF rep1" )
    for dev in eth0 eth1 eth2; do
        if ! exec_in_ns0 test -e /sys/class/net/$dev ; then
            device_restore_root_ns
            fail "${role_map[$dev]}($dev) is not found in netns ns0."
        fi
    done

    title "Verify VF reps are cleaned up from within a net namespace when SRIOV is disabled."
    exec_pf_in_ns0 config_sriov 0
    for dev in eth1 eth2; do
        exec_in_ns0 test -e /sys/class/net/$dev && err "${role_map[$dev]}($dev) is not destroyed."
    done

    title "Verify VF reps would be evacuated from the ns upon ns deletion."
    exec_pf_in_ns0 config_sriov 2
    exec_pf_in_ns0 enable_switchdev
    num_devs_in_ns=`PF_IN_NS=ns0 get_reps_count eth0`
    if [ "$num_devs_in_ns" == 0 ]; then
        device_restore_root_ns
        fail "Got 0 reps in ns0"
    fi
    ip netns del ns0

    # Wait for driver/kernel to cleanup namespace
    sleep 10
    local num_devs_post_evacuation=`get_reps_count $NIC`
    if [ $num_devs_post_evacuation -ne 1 ]; then
        fail "Failed to evacuate all reps from ns"
    fi

    reload_modules
}

run

trap - EXIT
cleanup
test_done
