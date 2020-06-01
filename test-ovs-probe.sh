#!/bin/bash
#
# Test OVS probe of features don't use hw-offload so we won't get
# errors from the driver for unsupported attributes
#
# Bug SW #2148964

my_dir="$(dirname "$0")"
. $my_dir/common.sh

LOCAL_TUN=7.7.7.7
REMOTE_IP=7.7.7.8
VXLAN_ID=42

config_sriov 2
enable_switchdev_if_no_rep $REP
require_interfaces REP NIC
unbind_vfs
bind_vfs


function cleanup() {
    ip a flush dev $NIC
}
trap cleanup EXIT

function run() {
    cleanup
    ifconfig $NIC $LOCAL_TUN/24 up

    echo "Restarting OVS"
    start_clean_openvswitch
    ovs-vsctl set Open_vSwitch . other_config:hw-offload=false || fail "Failed to set ovs hw-offload=false"
    start_clean_openvswitch

    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs vxlan1 -- set interface vxlan1 type=vxlan options:local_ip=$LOCAL_TUN options:remote_ip=$REMOTE_IP options:key=$VXLAN_ID options:dst_port=4789
    ovs-vsctl add-port br-ovs $REP

    log "set ovs hw offload true"
    ovs-vsctl set Open_vSwitch . other_config:hw-offload=true
    restart_openvswitch

    check_for_err "Failed to parse tunnel attributes"

    start_clean_openvswitch
}


run
test_done
