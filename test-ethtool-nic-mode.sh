#!/bin/bash
#
# Verify nic ethtool features
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


function chk_lro() {
    local failed=0
    ethtool -K $NIC2 lro on || failed=1
    [ $failed == 1 ] && err "Failed to enable lro" && return
    ethtool -K $NIC2 lro off
    success
}

function do_test() {
    title "Verify nic ethtool features"

    title "test lro"
    chk_lro
}


config_sriov 0 $NIC2
do_test
test_done
