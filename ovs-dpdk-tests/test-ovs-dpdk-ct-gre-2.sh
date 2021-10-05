#!/bin/bash
#
# Test OVS-DPDK with gre traffic
# having OVS-DPDK on both sides to cover
# cases which gre tunnel is not supported by kernel
#
# Require external server
#
# IGNORE_FROM_TEST_ALL

my_dir="$(dirname "$0")"
. $my_dir/../common.sh
. $my_dir/common-dpdk.sh

require_remote_server

cleanup_test
remote_ovs_cleanup

gre_set_entropy
gre_set_entropy_on_remote


config_2_side_tunnel gre
ovs_add_ct_rules

verify_ping

generate_traffic "remote" $LOCAL_IP ns0

# check offloads
check_dpdk_offloads $LOCAL_IP
check_offloaded_connections 5


cleanup_test
remote_ovs_cleanup
test_done
