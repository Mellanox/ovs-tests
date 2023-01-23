#!/bin/bash
#
# Test interoperability of net namesapces and SRIOV/swtichdev mode
#
# [MLNX OFED] RM #3253350: CX6DX Container offload: support PF/Rep inside namespace
#
# The test cases are mainly to verify the rules:
# 1. PF/uplink REP can be moved in/out of a network namespace if
#    either SRIOV is not enabled or eswitch is not in switchdev mode
# 2. Any REP, uplink or VF's, can not be moved to another network
#    namespace if SRIOV is enabled and eswitch is in switchdev mode
# 3. Representors are not lost/leaked if they were in a network
#    namespace that is deleted, instead, they are evacuated to the
#    root namespace.
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

function cleanup() {
    config_sriov 0
    enable_legacy
    ip netns del ns0 &>/dev/null
    sleep 1
}

trap cleanup EXIT

function run() {
    cleanup
    title "Verify uplink rep $NIC cannot be added to ns if sriov is enabled and in switchdev mode."
    config_sriov 2
    enable_switchdev
    ip netns add ns0
    ip l set dev $NIC netns ns0 && err "Expected to fail adding $NIC to ns0."
    cleanup

    title "Verify uplink rep $NIC can be moved among network namespaces if sriov is disabled and in switchdev mode."
    ip netns add ns0
    config_sriov 0
    enable_switchdev
    ip l set dev $NIC netns ns0 2>/dev/null || err "Failed to add $NIC to ns0."
    cleanup

    title "Verify PF $NIC can be moved among network namespaces if sriov is enabled and in legacy mode."
    ip netns add ns0
    enable_legacy
    config_sriov 2
    ip l set dev $NIC netns ns0 2>/dev/null || err "Failed to add $NIC to ns0."
    cleanup

    title "Verify VF reps would be created inside network namespace that uplink rep is in."
    ip netns add ns0
    ip l set dev $NIC netns ns0 || err "Failed to add $NIC to ns0."
    config_sriov 2
    enable_switchdev
    local reps_in_ns=1
    declare -A role_map=( [$NIC]="Uplink rep" ["eth0"]="VF rep0" ["eth1"]="VF rep1" )
    for dev in $NIC eth0 eth1; do
        if ! ip netns exec ns0 test -e /sys/class/net/$dev ; then
            err "${role_map[$dev]}($dev) is not found in netns ns0."
            reps_in_ns=0
        fi
    done

    if [ "$reps_in_ns" == 1 ]; then
        title "Verify VF reps are cleaned up from within a net namespace when SRIOV is disabled."
        config_sriov 0
        for dev in eth0 eth1; do
            ip netns exec ns0 test -e /sys/class/net/$dev && err "${role_map[$dev]}($dev) is not destroyed."
        done

        title "Verify VF reps would be evacuated from the ns upon ns deletion."
        config_sriov 2
        enable_switchdev
        local num_devs_in_ns=`PF_IN_NS=ns0 get_reps_count $NIC`
        if [ "$num_devs_in_ns" == 0 ]; then
            err "Got 0 reps in ns0"
        fi
        ip netns del ns0
        sleep 1
        local num_devs_post_evacuation=`get_reps_count $NIC`
        if [ $num_devs_post_evacuation -ne $num_devs_in_ns ]; then
            err "Failed to evacuate all reps from ns"
        fi
    fi
}

run

trap - EXIT
cleanup
test_done
