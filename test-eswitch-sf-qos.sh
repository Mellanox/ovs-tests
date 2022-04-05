#!/bin/bash
#
# Test checks that creating SF QoS group does not cause a setup hang.
# [MLNX OFED] Bug SW #3020769: supervisor restarts when SF group is opened
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-sf.sh

trap remove_sfs EXIT

function config() {
    create_sfs 1
    fail_if_err "Failed to create sfs"
    title "Create QoS group #12"
    sf_create_qos_group 12
    sf_delete_qos_group 12
}

enable_norep_switchdev $NIC
config
test_done
