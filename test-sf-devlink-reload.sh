#!/bin/bash
#
# Test SF EQ memory optimizations memory check
#
# Bug SW #3207544: [Upstream] MAX_LOCKDEP_CHAIN_HLOCKS too low

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-sf.sh
. $my_dir/common-devlink.sh

function cleanup() {
    remove_sfs
}
trap cleanup EXIT

SF_NUM=12

function run_test() {
    config_sriov 0 $NIC
    enable_switchdev $NIC
    create_sfs $SF_NUM

    log "reload SFs"
    for dev in `devlink_get_sfs`; do
        devlink_dev_reload $dev
    done
    remove_sfs
}

run_test

log "cleanup"
trap - EXIT
cleanup
test_done
