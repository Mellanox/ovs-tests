#!/bin/bash
#
# Verify ethtool changing other channels on VF rep
# Expect not to crash.
#
# Bug SW #2244416: OFED 5.1 Call trace and kernel panic when trying to set channels on VF representor
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

config_sriov 2 $NIC
enable_switchdev

title "Test set other channels on VF rep"

function run() {
    local chans=$1
    log "test chans $chans"
    ethtool -L $REP other $chans || fail "ethtool command failed"
}

run 2
run 4
# crash happened with high number
run 40

test_done
