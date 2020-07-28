#!/bin/bash
#
# Verify default hw-tc-offload on uplink rep is on
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_interfaces NIC
reload_modules
config_sriov 2
enable_switchdev
value=`ethtool -k $NIC | grep hw-tc-offload | awk {'print $2'}`

if [ "$value" != "on" ]; then
    err "Expected hw-tc-offload=on"
fi

test_done
