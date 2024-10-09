#!/bin/bash
#
# Test OVS-DPDK VF-VF traffic
# Use action move tcp port to ia register to make ovs create multiple rules (rule per tcp port).
# Set ctl-pipe-size to a low number to cause a resize.
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

config_sriov 2
enable_switchdev
bind_vfs

trap cleanup EXIT

function cleanup() {
    ovs_conf_remove ctl-pipe-size
    cleanup_test
}

function config() {
    cleanup

    config_simple_bridge_with_rep 2
    config_ns ns0 $VF $LOCAL_IP
    config_ns ns1 $VF2 $REMOTE_IP
    ovs_conf_set ctl-pipe-size 10
    restart_openvswitch

    local bridge="br-phy"
    exec_dbg "ovs-ofctl -O OpenFlow13 add-flow $bridge \"in_port=pf0vf0,ip,tcp,actions=move:NXM_OF_TCP_DST->NXM_NX_REG12[0..15],pf0vf1\"" || err "Failed adding rule"
    exec_dbg "ovs-ofctl -O OpenFlow13 add-flow $bridge \"in_port=pf0vf1,ip,tcp,actions=move:NXM_OF_TCP_SRC->NXM_NX_REG12[0..15],pf0vf0\"" || err "Failed adding rule"
    ovs-ofctl -O OpenFlow13 dump-flows $bridge --color
}

function run() {
    config

    verify_ping $REMOTE_IP ns0
    generate_traffic "local" $LOCAL_IP ns1 true ns0 local 5 19
    sleep 2
    check_resize_counter
}

run
trap - EXIT
cleanup_test
test_done
