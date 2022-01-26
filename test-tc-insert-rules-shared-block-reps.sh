#!/bin/bash
#
# Test shared block on two reps
# Feature #2914423: VF share block (ingress block)

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module act_ct

config_sriov 2
enable_switchdev
require_interfaces REP REP2
unbind_vfs
bind_vfs

function cleanup() {
    reset_tc $REP
    reset_tc $REP2
}
trap cleanup EXIT

function test_shared_block_reps() {
    title "Test shared block on reps"

    echo "Add $REP and $REP2 to shared block with index 11"
    reset_tc_block_index 11 $REP $REP2

    echo "add rule"
    tc_filter add block 11 prio 2 protocol ip flower dst_mac aa:bb:cc:dd:ee:ff skip_sw action drop

    verify_in_hw $REP 2
    verify_in_hw $REP2 2
}

cleanup
test_shared_block_reps
test_done
