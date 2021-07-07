#!/bin/bash
#
# Test if dynamic MSI-X VF queue is supported
#
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

function run() {
    title "Test MSI-X"

    echo "Enable sriov on $NIC, nums 2"
    config_sriov 2 $NIC
    enable_legacy $NIC
    vf_pci=$(basename `readlink /sys/class/net/$NIC/device/virtfn0`)
    if [ -z "$vf_pci" ]; then
        fail "No VF found!"
    fi

    echo "Check default MSI-X of $vf_pci config"
    orig_cnt=`lspci -vs $vf_pci | grep "MSI-X:" | grep -o -E "Count=([0-9]+)" | cut -d= -f2`
    if [ -z "$orig_cnt" ]; then
        fail "MSI-X is not enabled"
    fi

    new_cnt=21
    echo "Change MSI-X of $vf_pci from $orig_cnt to $new_cnt"
    echo $new_cnt > /sys/bus/pci/devices/${vf_pci}/sriov_vf_msix_count
    if [ $? -ne 0 ]; then
        fail "Error to set MSI-X queue count for VF"
    fi
    echo $orig_cnt > /sys/bus/pci/devices/${vf_pci}/sriov_vf_msix_count
}

run
test_done
