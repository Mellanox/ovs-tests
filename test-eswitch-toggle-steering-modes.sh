#!/bin/bash
#
# Test toggle steering modes (smfs, dmfs) to make sure nothing breaks.
#
# Bug SW #2581081: [Upstream][SW Steering] Fail to switch mode to switchdev over full debug kernel

my_dir="$(dirname "$0")"
. $my_dir/common.sh

user_steering_mode=`get_flow_steering_mode $PCI`
if [ -z "$user_steering_mode" ]; then
    fail "Steering mode is not supported"
fi
current_steering_mode=$user_steering_mode

function toggle_steering_mode() {
    if [ "$current_steering_mode" == "smfs" ]; then
        current_steering_mode="dmfs"
    elif [ "$current_steering_mode" == "dmfs" ]; then
        current_steering_mode="smfs"
    else
        fail "Invalid steering mode"
    fi

    set_flow_steering_mode $PCI $current_steering_mode
    set_flow_steering_mode $PCI2 $current_steering_mode
    echo "Flow steering mode for $PCI is now `get_flow_steering_mode $PCI`"
    echo "Flow steering mode for $PCI2 is now `get_flow_steering_mode $PCI2`"
}

function loop_toggle_modes() {
    local i
    for i in `seq 3`; do
        title "Toggle steering mode $i"
        enable_legacy
        toggle_steering_mode
        enable_switchdev
    done
}

function restore_steering_mode() {
    title "Restore user steering mode"
    enable_legacy
    set_flow_steering_mode $PCI $user_steering_mode
    set_flow_steering_mode $PCI2 $user_steering_mode
    enable_switchdev
}

config_sriov 2
enable_legacy
loop_toggle_modes
restore_steering_mode
test_done
