#!/bin/bash
#
# Test enabling age_ct_based_on_pps for custom mlnx ofed.
# age_ct_based_on_pps - Defines whether to use aggressive throughput-based eviction, or to fall back on passive,
# idle-based timeout. The default is disabled (0). Note, disabled is 0, enabled is 1.
#
# IGNORE_FROM_TEST_ALL

my_dir="$(dirname "$0")"
. $my_dir/common.sh

CONF_NAME=age_ct_based_on_pps

title "Checking that $CONF_NAME is supported"
modinfo mlx5_core|grep -q $CONF_NAME

if [[ $? -eq 0 ]]; then
    success "CONFIG $CONF_NAME is supported"
else
    fail "CONFIG $CONF_NAME is not supported"
fi

title "Checking if $CONF_NAME is enabled"
value=`cat /sys/module/mlx5_core/parameters/$CONF_NAME`

if [[ $value -eq 1 ]]; then
    fail "$CONF_NAME is already enabled"
fi

title "Enabling $CONF_NAME"
echo "options mlx5_core $CONF_NAME=1" > /etc/modprobe.d/mlx5_ct_agent.conf
reload_modules

value=`cat /sys/module/mlx5_core/parameters/$CONF_NAME`

if [[ $value -eq 1 ]]; then
    success
else
    fail "Failed to enable $CONF_NAME"
fi

test_done