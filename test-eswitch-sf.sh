#!/bin/bash
#
# Test SF add/delete commands
#
# required mlxconfig is PF_BAR2_SIZE=3 PF_BAR2_ENABLE=1
# pci rescan or cold reboot is required.

my_dir="$(dirname "$0")"
. $my_dir/common.sh

function verify_mlxconfig_for_sf() {
    SF_BAR2_ENABLED="True(1)"
    bar2_enable=`fw_query_val PF_BAR2_ENABLE`
    echo "PF_BAR2_ENABLE=$bar2_enable"
    if [ "$bar2_enable" != "$SF_BAR2_ENABLED" ]; then
        fail "Cannot support SF with current mlxconfig settings"
    fi
}

function sf_port_add_del_test() {
    title "Test sf port add delete commands"

    devlink port add pci/$PCI flavour pcisf pfnum 0 sfnum 88 || fail "Failed to add SF"
    sleep 1
    local rep=`devlink port show | grep "pfnum 0 sfnum 88" | grep -E -o "netdev [a-z0-9]+" | awk {'print $2'}`
    devlink port show $rep || err "Failed to show SF"
    devlink port del $rep || err "Failed to del SF"
}

verify_mlxconfig_for_sf
enable_norep_switchdev $NIC
sf_port_add_del_test

test_done
