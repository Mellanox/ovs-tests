#!/bin/bash
#
# Test SF add/delete commands
#
# required mlxconfig is PF_BAR2_SIZE=3 PF_BAR2_ENABLE=1
# pci rescan or cold reboot is required.

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-sf.sh

function sf_port_add_del_test() {
    create_sf 0 88
    fail_if_err
    sleep 1
    local rep=`sf_get_rep 88`
    sf_show_port $rep
    delete_sf $rep
    fail_if_err
}

function test_add_del_loop() {
    for iter in 1 2 ; do
        title "iter $iter"
        sf_port_add_del_test
    done
}

function sf_without_sriov() {
    title "Test sf ports without sriov"
    config_sriov 0 $NIC
    enable_switchdev $NIC
    test_add_del_loop
}

function sf_with_sriov() {
    title "Test sf ports with sriov"
    config_sriov 2 $NIC
    enable_switchdev $NIC
    test_add_del_loop
}

sf_without_sriov
sf_with_sriov

test_done
