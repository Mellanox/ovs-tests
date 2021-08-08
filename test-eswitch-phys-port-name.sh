#!/bin/bash
#
# Test pfs, vfs, reps phys_port_name and phys_switch_id are readable
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


config_sriov 2
enable_switchdev
bind_vfs

# enough to check once of each
require_interfaces NIC VF REP

function verify_phys_port_name() {
    local nic=$1
    # don't care if doesn't exists or not readable. maybe old kernel?
    if [ ! -r /sys/class/net/$nic/phys_port_name ]; then
        return
    fi
    title "Try to read phys_port_name for $nic"
    cat /sys/class/net/$nic/phys_port_name || err "Failed to read phys_port_name"
    title "Try to read phys_switch_id for $nic"
    cat /sys/class/net/$nic/phys_switch_id || err "Failed to read phys_switch_id"
}

verify_phys_port_name $NIC
verify_phys_port_name $VF
verify_phys_port_name $REP

test_done
