#!/bin/bash
#
# Test change trust to dscp
# When both ports up and we try to configure qos,
# we get an error creating sqs in kernel 3.10 with ofed 4.7.
# [MLNX OFED] Bug SW #1976431: [VF-LAG] Port stuck after configuring pfc and ecn
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

function config() {
    config_sriov 0
    config_sriov 0 $NIC2
    config_sriov 2
    config_sriov 2 $NIC2
    unbind_vfs
    unbind_vfs $NIC2
    enable_switchdev
    enable_switchdev $NIC2
    reset_tc $NIC $NIC2
}

function config_qos() {
    # issue happens when both ports up
    ifconfig $NIC up
    ifconfig $NIC2 up
    mlnx_qos -i $NIC2 --trust dscp
    mlnx_qos -i $NIC --trust dscp
}

function cleanup() {
    config_sriov 0
    config_sriov 0 $NIC2
}


title "Test qos"
cleanup
config
config_qos
a=`journalctl --since="5 seconds ago" | grep "Failed to add"`
if [ -n "$a" ]; then
    err "$a"
fi
cleanup

test_done
