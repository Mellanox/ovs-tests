#!/bin/bash
#
# Bug SW #1056223: kernel oops when calling devlink show and hca is in
# infiniband mode
#
# Requires CX-5 (MT4121)
#

NIC=${1:-ens5f0}
my_dir="$(dirname "$0")"
. $my_dir/common.sh

# not relevant for cx4lx because it doesn't support link_type
not_relevant_for_cx4lx
require_mlxconfig


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

title "Test devlink show in IB mode"
set_link_type_ib || fail
fw_reset
devlink_eswitch_show
success

title "Test devlink show in ETH mode"
set_link_type_eth || fail
fw_reset
devlink_eswitch_show
success

set_macs 2
check_syndrome
check_kasan
test_done
