#!/bin/bash
#
# Bug SW #1124753: VF is in no-carrier state in legacy mode after bringup of its
# representor in switchdev mode
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

function config_port() {
    config_sriov 0
    config_sriov 2
    unbind_vfs
    enable_switchdev_if_no_rep $REP
    set_macs 2
    bind_vfs
    sleep 1
}

function do_test() {
    # bring up rep is what triggers the issue
    require_interfaces REP
    ip link set dev $REP up
    switch_mode_legacy
    sleep 1
    require_interfaces NIC VF
    echo "bring up interfaces"
    ip link set dev $NIC up
    ip link set dev $VF up
    sleep 1
}

function test_carrier() {
    carrier=`cat /sys/class/net/$VF/carrier`

    if [ "$carrier" == "0" ]; then
        ip link show dev $VF
        err "VF $VF has no carrier"
        return
    fi
    success
}

function config_two_ports() {
    config_sriov 0
    config_sriov 0 $NIC2
    config_sriov 2
    config_sriov 2 $NIC2
    unbind_vfs
    unbind_vfs $NIC2
    enable_switchdev
    bind_vfs
    config_sriov 0 $NIC2
}

function pre_step() {
    # bug sometimes reproduce after setting sriov and then cleaning it.
    # so lets do that as first step before all cases.
    title "pre step"
    config_sriov 2
    config_sriov 0
}


pre_step

title "Test one port config"
config_port
do_test
test_carrier

title "Test two ports config"
# we saw issue start reproducing after configuring two ports.
config_two_ports
do_test
test_carrier
if [ $TEST_FAILED == 1 ]; then
    # next run port one also fails. so for consistency between runs,
    # reload the modules.
    reload_modules
    config_port
fi

test_done
