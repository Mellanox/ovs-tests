#!/bin/bash
#
# Bug SW #2094097: [Upstream] Fail to switch mode to switchdev while ESWITCH_IPV4_TTL_MODIFY_ENABLE is enabled

my_dir="$(dirname "$0")"
. $my_dir/common.sh

relevant_for_cx5
require_mlxconfig

function set_eswitch_ipv4_ttl_modify_enable() {
    local mode=$1
    fw_config ESWITCH_IPV4_TTL_MODIFY_ENABLE=$mode
}


function cleanup() {
    title "- disable ipv4 ttl modify"
    set_eswitch_ipv4_ttl_modify_enable false
    fw_reset
    config_sriov 2
}


title "Test set switchdev dev when eswitch ipv5 ttl modify enabled"
trap cleanup EXIT
start_check_syndrome

title "- enable ipv4 ttl modify"
set_eswitch_ipv4_ttl_modify_enable true || fail "Cannot set eswitch ipv4 ttl modify enable"
fw_reset

title "- set switchdev"
config_sriov 2
enable_switchdev_if_no_rep $REP

trap - EXIT
cleanup
check_syndrome
test_done
