#!/bin/bash
#
# Test dpdk starting with vf lag on ports that one has flow control enable and one disabled.
#
# [MLNX DPDK] Bug SW #3601477: [MLNX_DPDK][VF_LAG] Seg fault in mlx5_os_read_dev_counters() after
# running in non-lag mode then configuring lag and running testpmd

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh
. $my_dir/../common-sf.sh

enable_switchdev

function cleanup() {
    ethtool -A $NIC2 tx off rx off
    clean_vf_lag
    cleanup_test
}

trap cleanup EXIT

function clean_vf_lag() {
    # must unbind vfs to create/destroy lag
    unbind_vfs $NIC
    unbind_vfs $NIC2
    clear_bonding
}

function config_vf_lag() {
    local mode=${1:-"802.3ad"}

    config_sriov 2 $NIC
    config_sriov 2 $NIC2
    enable_switchdev $NIC
    enable_switchdev $NIC2
    config_bonding $NIC $NIC2 $mode
    is_vf_lag_activated || fail
    bind_vfs $NIC
    bind_vfs $NIC2

    ethtool -A $NIC tx off rx off
    ethtool -A $NIC2 tx on rx on
}

function config() {
    config_vf_lag
}

function run() {
    cleanup
    config
    tail -f /dev/null | timeout 4 $testpmd -a "$PCI,$DPDK_PORT_EXTRA_ARGS" --  --total-num-mbufs=4096
    if [ $? -eq 124 ]; then
        # 124 is timeout so testpmd was running.
        success
    else
        err
    fi
}

run
trap - EXIT
cleanup
test_done
