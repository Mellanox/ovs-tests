#!/bin/bash
#
# Test add/del CT rule
#
# Bug SW #2911525: [sw steering] syndrome icm out of memory when alloc/dealloc lots of modify hdr rules

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module act_ct

config_sriov 2
enable_switchdev
require_interfaces NIC

function cleanup() {
    reset_tc $NIC
}
trap cleanup EXIT

function run() {
    local i
    local count=3500

    title "Test add/del CT rule $count iterations"

    reset_tc $NIC
    for i in `seq $count`; do
# took 3277 iterations to fail with ct rule
        tc_filter add dev $NIC ingress protocol ip prio 2 flower skip_sw \
            dst_mac e2:11:22:33:44:55 ct_state -trk \
            action ct action goto chain 1 || err "Failed to offload tc rule, iteration $i"
# took 8192 iterations to fail with pedit rule
#        tc_filter add dev $NIC ingress protocol ip prio 2 flower skip_sw \
#            dst_mac e2:11:22:33:44:55 \
#            action pedit ex munge eth dst set e2:11:22:33:44:66 pipe \
#            action goto chain 1 || err "Failed to offload tc rule, iteration $i"
        reset_tc $NIC
        fail_if_err
    done
}

cleanup
run
test_done
