#!/bin/bash
#
# Try to change hash function and check no syndrome
#
# Bug SW #1614845: [JD] Syndrome when when changing RSS hash func
# Bug SW #1630228: tunnel stateless offloads are wrongly forbidden for e-switch manager function

my_dir="$(dirname "$0")"
. $my_dir/common.sh


function change_hfunc() {
    title "Test change hashfunc for $NIC"

    start_check_syndrome
    # make sure in sriov and switchdev
    config_sriov 2 $NIC
    enable_switchdev

    log "set hfunc toeplitz"
    ethtool -X $NIC hfunc toeplitz || err "Failed to set hfunc toeplitz"
    log "set hfunc xor"
    ethtool -X $NIC hfunc xor || err "Failed to set hfunc xor"
    check_syndrome
}


change_hfunc
test_done
