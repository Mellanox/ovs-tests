#!/bin/bash
#
# Bug SW #1056223: kernel oops when calling devlink show and hca is in
# infiniband mode
#
# Requires CX-5 (MT4121)
#
# IGNORE_FROM_TEST_ALL

NIC=${1:-ens5f0}
my_dir="$(dirname "$0")"
. $my_dir/common.sh


require_mlxconfig
# not relevant for cards that don't support multiple link_type like cx4lx
require_fw_opt LINK_TYPE_P1

function set_link_type() {
    local mode=$1
    mlxconfig -y -d $PCI set LINK_TYPE_P1=$mode LINK_TYPE_P2=$mode || err "mlxconfig failed"
}

function set_link_type_ib() {
    set_link_type IB
}

function set_link_type_eth() {
    set_link_type ETH
}

function devlink_eswitch_show() {
    devlink dev eswitch show pci/$PCI
}


start_check_syndrome

# setting steering mode is not working with IB mode as we use eth NIC mode
# and also its not needed for this test so lets skip it.
unset STEERING_MODE

title "Test devlink show in IB mode"
set_link_type_ib || fail
fw_reset
config_sriov 2
devlink_eswitch_show
success

title "Test devlink show in ETH mode"
set_link_type_eth || fail
fw_reset
config_sriov 2
devlink_eswitch_show
success

set_macs 2
check_syndrome
check_kasan
test_done
