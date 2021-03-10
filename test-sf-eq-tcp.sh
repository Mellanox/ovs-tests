#!/bin/bash
#
# Test SF EQ memory optimizations while changing the eq configuration and running tcp connection.
#
# required mlxconfig is PF_BAR2_SIZE=3 PF_BAR2_ENABLE=1
# [MKT. BlueField-SW] Feature Request #2482519: EQ memory optimizations - OFED first
# [MLNX OFED] Bug SW #2248656: [MLNX OFED SF] Creating SF is causing a kfree for unknown address

my_dir="$(dirname "$0")"
. $my_dir/common.sh

if ! is_ofed ; then
    fail "This feature is supported only over OFED"
fi

require_cmd uuidgen
verify_mlxconfig_for_sf

IP1="7.7.7.1"
IP2="7.7.7.2"
UUID1=$(uuidgen)
UUID2=$(uuidgen)

function cleanup() {
    start_clean_openvswitch
    remove_sf
}

trap cleanup EXIT

function remove_ns(){
    ip netns del ns0 &> /dev/null
    ip netns del ns1 &> /dev/null
    ovs_clear_bridges
}

function create_sf() {
    title "Create SFs with RoCE Disabled"
    for uuid in $UUID1 $UUID2; do
        echo $uuid > /sys/class/infiniband/mlx5_0/device/mdev_supported_types/mlx5_core-local/create
        echo $uuid > /sys/bus/mdev/drivers/vfio_mdev/unbind
        echo 1 > /sys/bus/mdev/devices/$uuid/devlink-compat-config/roce_disable
        echo $uuid > /sys/bus/mdev/drivers/mlx5_core/bind
        sleep 1
    done
}

function set_eq_config(){
    title "Configure SFs EQ"
    echo "max_cmpl_eq_count: $1"
    echo "cmpl_eq_depth: $2"
    echo "async_eq_depth: $3"

    for uuid in $UUID1 $UUID2; do
        echo $uuid > /sys/bus/mdev/drivers/mlx5_core/unbind
        echo $1 > /sys/bus/mdev/devices/$uuid/devlink-compat-config/max_cmpl_eq_count
        echo $2 > /sys/bus/mdev/devices/$uuid/devlink-compat-config/cmpl_eq_depth
        echo $3 > /sys/bus/mdev/devices/$uuid/devlink-compat-config/async_eq_depth
        echo $uuid > /sys/bus/mdev/drivers/mlx5_core/bind
        sleep 1
    done
}

function remove_sf() {
    title "Delete SFs"
    for uuid in $UUID1 $UUID2; do
        echo 1 > /sys/bus/mdev/devices/$uuid/remove
    done
}

function config() {
    title "Config"
    start_clean_openvswitch
    create_sf
}

function get_sf_netdev_rep() {
    title "SFs Netdev Rep Info"
    SF=$(basename `ls /sys/class/net/$NIC/device/$UUID1/net`)
    SF_REP=$(cat /sys/bus/mdev/devices/$UUID1/devlink-compat-config/netdev)
    echo "SF: $SF, REP: $SF_REP"
    SF1=$(basename `ls /sys/class/net/$NIC/device/$UUID2/net`)
    SF_REP1=$(cat /sys/bus/mdev/devices/$UUID2/devlink-compat-config/netdev)
    echo "SF: $SF1, REP: $SF_REP1"

}

function config_ns() {
    config_vf ns0 $SF $SF_REP $IP1
    config_vf ns1 $SF1 $SF_REP1 $IP2
    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $SF_REP
    ovs-vsctl add-port br-ovs $SF_REP1
}

function run_traffic() {
    t=15
    echo "run traffic for $t seconds"
    ip netns exec ns1 timeout $((t+1)) iperf -s &
    sleep 0.5
    ip netns exec ns0 timeout $((t+1)) iperf -t $t -c $IP2 -P 3 &

    sleep 2
    pidof iperf &>/dev/null || err "iperf failed"

    echo "sniff packets on $SF_REP"
    timeout $((t-4)) tcpdump -qnnei $SF_REP -c 10 'tcp' &
    pid1=$!

    sleep $t
    killall -9 iperf &>/dev/null
    wait $! 2>/dev/null

    title "test traffic offload"
    verify_no_traffic $pid1
}

function run() {
    max_cmpl_eq_count=1
    cmpl_eq_depth=256
    async_eq_depth=1024

    for i in 1 2 3; do
        title "Case $i"
        set_eq_config $(($max_cmpl_eq_count * $i)) $(($cmpl_eq_depth * $i)) $(($async_eq_depth * $i))
        get_sf_netdev_rep
        config_ns
        run_traffic
        remove_ns
    done
}

config
run
cleanup
trap - EXIT
test_done
