#!/bin/bash
#
# Test toggle e-switch mode and expect to fail
# Purpose to test the error flow. for issue, memleak, etc.
#
# Bug SW #2431774: memleak when failing to change to switchdev mode

my_dir="$(dirname "$0")"
. $my_dir/common.sh


enable_legacy
bind_vfs
__ignore_errors=1
switch_mode_switchdev
__ignore_errors=0

m=`get_eswitch_mode`
if [ "$m" == "legacy" ]; then
    success "Expected to fail"
else
    err "Expected to fail"
fi

if is_ofed ; then
    reload_modules
fi

test_done
