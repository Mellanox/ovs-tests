#!/bin/bash
#
# Test sriov autoprobe
#
# Bug SW #2864113: [Upstream] Disable sriov_drivers_autoprobe blocks manual VFs binding

my_dir="$(dirname "$0")"
. $my_dir/common.sh

function cleanup() {
    restore_sriov_autoprobe
}

trap cleanup EXIT

disable_sriov_autoprobe
config_sriov 2

title "Test bind of VFs when autoprobe is enabled"
enable_sriov_autoprobe
unbind_vfs
bind_vfs && success || err "Failed to bind"

title "Test bind of VFs when autoprobe is disabled"
disable_sriov_autoprobe
unbind_vfs
bind_vfs && success || err "Failed to bind"

test_done
