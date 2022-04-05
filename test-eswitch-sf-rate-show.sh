#!/bin/bash
#
# Test checks that printing sf rate does not cause a setup hang.
# [MLNX OFED] Bug SW #3020686: [dpu_nic] server reset after running "port function rate show" on sfs
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-sf.sh

trap remove_sfs EXIT

function config() {
    create_sfs 1
    fail_if_err "Failed to create sfs"
    title "Show SF rate"
    sf_rate_show
}

enable_norep_switchdev $NIC
config
test_done
