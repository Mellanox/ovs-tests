#!/bin/bash
#
# Verify nic ethtool features
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


function chk_lro() {
    local failed=0
    ethtool -K $NIC2 lro on || failed=1
    [ $failed == 1 ] && err "Failed to enable LRO" && return
    ethtool -K $NIC2 lro off
    success
}

function chk_rx_striding_rq() {
    local failed=0
    local rx_striding_rq=`ethtool --show-priv-flags ${NIC2} | grep rx_striding_rq | awk {'print $3'}`
    if [ "$rx_striding_rq" == "off" ]; then
        ethtool --set-priv-flags $NIC2 rx_striding_rq on || failed=1
        [ $failed == 1 ] && err "Failed to enable rx_striding_rq" && return
        success
    fi

}

function do_test() {
    title "Verify nic ethtool features"
    title "Test rx_striding_rq"
    chk_rx_striding_rq
    title "Test LRO"
    chk_lro
}


config_sriov 0 $NIC2
enable_legacy $NIC2
do_test
test_done
