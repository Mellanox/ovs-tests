#!/bin/bash
# Set VF rate limits:
#  - Case1: Expect not to crash
#     Reported by Tonghao Zhang <xiangxia.m.yue@gmail.com>
#     24319258660a net/mlx5: Avoid panic when setting vport rate
#  - Case2: Set min_tx_rate and max_tx_rate then read them to verify they were set as expected
#     [Kernel Upstream] Bug SW #2979654: [Upstream] Setting VF rate limits is not working properly


my_dir="$(dirname "$0")"
. $my_dir/common.sh

function config() {
    config_sriov 2
    enable_legacy
    bind_vfs
}

function cleanup() {
    config_sriov 0
    config_sriov 2
    enable_switchdev
}

function set_vf_rates_via_dev_vf() {
    title "Case 1: Set vf min_tx_rate & max_tx_rate via dev vf ($VF)"
    echo "  - Expect not to crash"
    ip link set dev $VF vf 0 min_tx_rate 1 max_tx_rate 2 2>/dev/null
    ip link set dev $VF vf 0 min_tx_rate -1 max_tx_rate -1 2>/dev/null
    success
}

function set_vf_rates_via_dev_pf() {
    title "Case 2: Set vf min_tx_rate & max_tx_rate via dev pf ($NIC)"
    ip link set dev $NIC vf 0 min_tx_rate 3 max_tx_rate 7

    echo "  - Verify"
    ip link show dev $NIC | grep "vf 0" | grep "max_tx_rate 7Mbps, min_tx_rate 3Mbps"

    if [[ $? -eq 0 ]]; then
        success
    else
        err "Mismatched vf rate limits"
    fi
}
trap cleanup EXIT
config
set_vf_rates_via_dev_vf
set_vf_rates_via_dev_pf
trap - EXIT
cleanup
test_done
