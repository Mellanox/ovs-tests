#!/bin/bash

DIR=$(cd `dirname $0` ; pwd)
SET_MACS="$DIR/set-macs.sh"

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


VENDOR_MELLANOX="0x15b3"

<<EOT
    { PCI_VDEVICE(MELLANOX, 0x1011) },                  /* Connect-IB */
    { PCI_VDEVICE(MELLANOX, 0x1012), MLX5_PCI_DEV_IS_VF},       /* Connect-IB VF */
    { PCI_VDEVICE(MELLANOX, 0x1013) },                  /* ConnectX-4 */
    { PCI_VDEVICE(MELLANOX, 0x1014), MLX5_PCI_DEV_IS_VF},       /* ConnectX-4 VF */
    { PCI_VDEVICE(MELLANOX, 0x1015) },                  /* ConnectX-4LX */
    { PCI_VDEVICE(MELLANOX, 0x1016), MLX5_PCI_DEV_IS_VF},       /* ConnectX-4LX VF */
    { PCI_VDEVICE(MELLANOX, 0x1017) },                  /* ConnectX-5, PCIe 3.0 */
    { PCI_VDEVICE(MELLANOX, 0x1018), MLX5_PCI_DEV_IS_VF},       /* ConnectX-5 VF */
    { PCI_VDEVICE(MELLANOX, 0x1019) },                  /* ConnectX-5, PCIe 4.0 */
    { PCI_VDEVICE(MELLANOX, 0x101a), MLX5_PCI_DEV_IS_VF},       /* ConnectX-5, PCIe 4.0 VF */
EOT

DEVICE_CX4_LX="0x1015"
DEVICE_CX5="0x1019"


function get_mlx_iface() {
    for i in /sys/class/net/* ; do
        if [ ! -r $i/device/vendor ]; then
            continue
        fi
        t=`cat $i/device/vendor`
        if [ "$t" == "$VENDOR_MELLANOX" ]; then
            . $i/uevent
            NIC=$INTERFACE
            echo "Found Mellanox iface $NIC"
            return
        fi
    done
}


function __setup_common() {
    if [ "$NIC" == "" ]; then
        return
    fi

    if [ ! -e /sys/class/net/$NIC/device ]; then
        fail "Cannot find NIC $NIC"
    fi

    PCI=$(basename `readlink /sys/class/net/$NIC/device`)
    echo "NIC $NIC PCI $PCI"

    DEVICE=`cat /sys/class/net/$NIC/device/device`
    DEVICE_IS_CX4=0
    DEVICE_IS_CX5=0
    if [ "$DEVICE" == "$DEVICE_CX4_LX" ]; then
        DEVICE_IS_CX4_LX=1
    elif [ "$DEVICE" == "$DEVICE_CX5" ]; then
        DEVICE_IS_CX5=1
    fi
}

function title2() {
    local title=${1:-`basename $0`}
    echo -e "${YELLOW}#############################################${BLACK}"
    echo -e "${YELLOW}# TEST $title${BLACK}"
    echo -e "${YELLOW}#############################################${BLACK}"
    if [ -w /dev/kmsg ]; then
        echo "************** TEST $title **************" > /dev/kmsg
    fi
}

function reset_tc() {
    local nic1="$1"
    tc qdisc del dev $nic1 ingress >/dev/null 2>&1  || true
    tc qdisc add dev $nic1 ingress
}

function reset_tc_nic() {
    local nic1="$1"
    ethtool -K $nic1 hw-tc-offload on
    reset_tc $nic1
}

function warn() {
    echo -e "${YELLOW}WARNING: $1$BLACK"
}

# print error and exit
function fail() {
    local m=${*-Failed}
    TEST_FAILED=1
    echo -e "${RED}ERROR: $m$BLACK"
    wait
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
    devlink dev eswitch show pci/$PCI | grep -o "\bmode [a-z]\+" | awk {'print $2'}
}

function get_eswitch_inline_mode() {
    devlink dev eswitch show pci/$PCI | grep -o "\binline-mode [a-z]\+" | awk {'print $2'}
}

function enable_switchdev() {
    unbind_vfs
    switch_mode_switchdev
    sleep 2 # wait for interfaces
}

function enable_switchdev_if_no_rep() {
    local rep=$1

    if [ ! -e /sys/class/net/$rep ]; then
        enable_switchdev
    fi
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

function get_sw_id() {
    cat /sys/class/net/$1/phys_switch_id 2>/dev/null
}

function get_rep() {
	local vf=$1
	local id=`get_sw_id $NIC`
	local id2
	local count=0

	if [ -z "$id" ]; then
	    echo "Cannot get switch id for $NIC"
	    exit 1
	fi

	VIRTUAL="/sys/devices/virtual/net"

	for i in `ls -1 $VIRTUAL`; do
	    id2=`get_sw_id $i`
	    if [ "$id" = "$id2" ]; then
		if [ "$vf" = "$count" ]; then
			echo $i
			echo "Found rep $i" >/dev/stderr
			return
		fi
		((count=count+1))
	    fi
	done
	echo "Cannot find rep index $vf" >/dev/stderr
	exit 1
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
    # avoid same time as start_check_syndrome
    sleep 1
    now=`date +"%s"`
    sec=`echo $now - $_check_syndrome_start + 1 | bc`
    a=`journalctl -n20 --since="$sec seconds ago" | grep -m1 syndrome || true`
    if [ "$a" != "" ]; then
        echo $a
        return 1
    fi
    return 0
}

function del_all_bridges() {
    ovs-vsctl list-br | xargs -r -l ovs-vsctl del-br 2>/dev/null
}

function start_clean_openvswitch() {
    del_all_bridges
    service openvswitch restart
    sleep 1
    del_all_bridges
}

function eval2() {
    local err
    eval $@
    err=$?
    test $err != 0 && err "Command failed: $@"
    return $err
}

function test_done() {
    wait
    test $TEST_FAILED == 0 && success "TEST PASSED" || fail "TEST FAILED"
}

function not_relevant_for_cx5() {
    if [ "$DEVICE_IS_CX5" = 1 ]; then
        echo "Test not relevant for ConnectX-5"
        exit 0
    fi
}


### main
title2 `basename $0`
__setup_common
start_test_timestamp
