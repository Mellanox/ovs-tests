#!/bin/bash
#
# Create bond on 2 reps
# Expect not to crash.
#
# Bug SW #2643910: create bond on 2 reps cause kernel crash

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module bonding
require_interfaces NIC NIC2


function config_shared_block() {
    for i in bond0 $REP $REP2 ; do
        tc qdisc del dev $i ingress &>/dev/null
        tc qdisc add dev $i ingress_block 22 ingress || err "Failed to add ingress_block"
    done
}

function config() {
    echo "- Config"
    config_sriov 2
    config_sriov 2 $NIC2
    enable_switchdev
    enable_switchdev $NIC2
    reset_tc $NIC $NIC2 $REP
    REP2=`get_rep 0 $NIC2`
    require_interfaces REP REP2
    # original issue reproduce with active-backup mode.
    __config_bonding $REP $REP2
    config_shared_block
}

function clean_shared_block() {
    for i in bond0 $NIC $NIC2 ; do
        tc qdisc del dev $i ingress_block 22 ingress &>/dev/null
    done
}

function cleanup() {
    clean_shared_block
    clear_bonding
    ifconfig $NIC down
}


trap cleanup EXIT
cleanup
config
fail_if_err
cleanup
test_done
