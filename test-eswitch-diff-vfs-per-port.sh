#!/bin/bash
#
# Bug SW #1244300: Crash reconfiguring SRIOV+switchdev more than once with
# different VFs per port
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

function do_test() {
    VF_COUNT_PF0=2
    VF_COUNT_PF1=1

    for i in `seq 2`; do
        config_sriov $VF_COUNT_PF0 $NIC
        config_sriov $VF_COUNT_PF1 $NIC2
        enable_switchdev $NIC
        enable_switchdev $NIC2
        bind_vfs
        sleep 2
    done

    config_sriov 2 $NIC
    config_sriov 0 $NIC2
}

do_test
test_done
