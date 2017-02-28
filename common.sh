#!/bin/bash

PCI=$(basename `readlink /sys/class/net/$NIC/device`)
echo "NIC $NIC PCI $PCI"
SET_MACS="/labhome/roid/scripts/ovs/set-macs.sh"


BLACK="\033[0;0m"
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[01;94m"

# global var to set if test fails. should change to error but never back to
# success.
TEST_FAILED=0
# global var to use for last error msg. like errno and %m.
ERRMSG=""


function title2() {
    local title=${1:-`basename $0`}
    echo "#############################################"
    echo "# TEST $title"
    echo "#############################################"
    echo "************** TEST $title **************" > /dev/kmsg
}

function reset_tc_nic() {
    local nic1="$1"

    # reset ingress
    tc qdisc del dev $nic1 ingress >/dev/null 2>&1  || true

    # add ingress
    tc qdisc add dev $nic1 ingress

    # activate hw offload
    ethtool -K $nic1 hw-tc-offload on
}

function warn() {
    echo -e "${YELLOW}WARNING: $1$BLACK"
}

# print error and exit
function fail() {
    local m=${*-Failed}
    TEST_FAILED=1
    echo -e "${RED}ERROR: $m$BLACK"
    exit 1
}

function err() {
    local m=${*-Failed}
    TEST_FAILED=1
    echo -e "${RED}ERROR: $m$BLACK"
}

function success() {
    local m=${1:-OK}
    echo -e "$GREEN$m$BLACK"
}

function title() {
    echo -e "$BLUE* $1$BLACK"
}

function switch_mode() {
    local extra="$2"
    echo "Change eswitch ($PCI) mode to $1 $extra"
    echo -n "Old mode: "
    devlink dev eswitch show pci/$PCI
    devlink dev eswitch set pci/$PCI mode $1 $extra || fail "Failed to set mode $1"
    echo -n "New mode: "
    devlink dev eswitch show pci/$PCI
    # bring up all interfaces
    ip link | grep DOWN | grep ens.*_[0-9] | cut -d: -f2 | xargs -I {} ip link set dev {} up
}

function switch_mode_legacy() {
    switch_mode legacy "$1"
}

function switch_mode_switchdev() {
    switch_mode switchdev "$1"
}

function get_eswitch_mode() {
    devlink dev eswitch show pci/0000:24:00.0 |grep -o "\bmode [a-z]\+" | awk {'print $2'}
}

function get_eswitch_inline_mode() {
    devlink dev eswitch show pci/0000:24:00.0 |grep -o "\binline-mode [a-z]\+" | awk {'print $2'}
}

function set_macs() {
    local count=$1
    $SET_MACS $NIC $count
}

function unbind_vfs() {
    for i in `ls -1d /sys/class/net/$NIC/device/virt*`; do
        vfpci=$(basename `readlink $i`)
        if [ -e /sys/bus/pci/drivers/mlx5_core/$vfpci ]; then
            echo "unbind $vfpci"
            echo $vfpci > /sys/bus/pci/drivers/mlx5_core/unbind
        fi
    done
}

function bind_vfs() {
    for i in `ls -1d /sys/class/net/$NIC/device/virt*`; do
        vfpci=$(basename `readlink $i`)
        if [ ! -e /sys/bus/pci/drivers/mlx5_core/$vfpci ]; then
            echo "bind vf $vfpci"
            echo $vfpci > /sys/bus/pci/drivers/mlx5_core/bind
        fi
    done
}

function start_test_timestamp() {
    # sleep to get a unique timestamp
    sleep 1
    _check_start_ts=`date +"%s"`
}

function check_kasan() {
    now=`date +"%s"`
    sec=`echo $now - $_check_start_ts + 1 | bc`
    a=`journalctl --since="$sec seconds ago" | grep -m1 KASAN || true`
    if [ "$a" != "" ]; then
        err $a
        return 1
    fi
    success "success"
    return 0
}

function start_check_syndrome() {
    # sleep to avoid check_syndrome catch old syndrome
    sleep 1
    _check_syndrome_start=`date +"%s"`
}

function check_syndrome() {
    if [ "$_check_syndrome_start" == "" ]; then
        fail "Failed checking for syndrome. invalid start."
        return 1
    fi
    now=`date +"%s"`
    sec=`echo $now - $_check_syndrome_start + 1 | bc`
    a=`journalctl -n20 --since="$sec seconds ago" | grep -m1 syndrome || true`
    if [ "$a" != "" ]; then
        echo $a
        return 1
    fi
    return 0
}

### common
title2 `basename $0`
start_test_timestamp
