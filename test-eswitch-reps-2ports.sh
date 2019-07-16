#!/bin/bash
#
# Test setting reps on both ports
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


probe_fs="/sys/class/net/$NIC/device/sriov_drivers_autoprobe"
probe=0
function disable_sriov_autoprobe() {
    if [ -e $probe_fs ]; then
        probe=`cat $probe_fs`
        echo 0 > $probe_fs
    fi
}

function restore_sriov_autoprobe() {
    if [ $probe == 1 ]; then
        echo 1 > $probe_fs
    fi
}

function cleanup() {
    restore_sriov_autoprobe
}

function test_reps() {
    local want=$1
    local nic=$2

    title "Test $want REPs on $nic"

    config_sriov 0 $nic
    echo "Config $want VFs"
    time config_sriov $want $nic
    echo

    unbind_vfs $nic
    echo "Set switchdev"
    time switch_mode_switchdev $nic
    echo

    echo "Verify"
    mac=`cat /sys/class/net/$nic/address | tr -d :`
    count=`grep $mac /sys/class/net/*/phys_switch_id 2>/dev/null | wc -l`
    # decr 1 for pf
    let count-=1
    if [ $count != $want ]; then
        err "Found $count reps but expected $want"
    else
        success "Got $count reps"
    fi

    # not cleaning up. testing both ports at the same time.
}


trap cleanup EXIT
start_check_syndrome
disable_sriov_autoprobe

test_reps 8 $NIC
test_reps 8 $NIC2

echo "Cleanup"
config_sriov 0 $NIC2
config_sriov 2 $NIC
cleanup
check_syndrome
test_done
