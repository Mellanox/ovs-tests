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
DEVICE_CX5_PCI_3="0x1017"
DEVICE_CX5_PCI_4="0x1019"

if [ `uname -r` = "3.10.0" ];  then
    backport_centos_7_2=1
elif [ `uname -r` = "3.10.0-327.el7.x86_64" ]; then
    backport_centos_7_2=1
fi


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

    if [ -n "$NIC2" ] && [ ! -e /sys/class/net/$NIC2/device ]; then
        fail "Cannot find NIC2 $NIC2"
    fi

    PCI=$(basename `readlink /sys/class/net/$NIC/device`)
    DEVICE=`cat /sys/class/net/$NIC/device/device`
    echo "NIC $NIC PCI $PCI DEVICE $DEVICE"

    DEVICE_IS_CX4=0
    DEVICE_IS_CX4_LX=0
    DEVICE_IS_CX5=0

    if [ "$DEVICE" == "$DEVICE_CX4_LX" ]; then
        DEVICE_IS_CX4=1
        DEVICE_IS_CX4_LX=1
    elif [ "$DEVICE" == "$DEVICE_CX5_PCI_3" ]; then
        DEVICE_IS_CX5=1
    elif [ "$DEVICE" == "$DEVICE_CX5_PCI_4" ]; then
        DEVICE_IS_CX5=1
    fi
}

function get_mst_dev() {
    mst start
    DEV=`mst status -v | grep -b net-$NIC | awk {'print $2'}`
    if [ "$DEV" == "NA" ]; then
        fail "Cannot get mst device"
        exit 1
    fi
    echo "DEV $DEV"
}

function kmsg() {
    local m=$@
    if [ -w /dev/kmsg ]; then
        echo ":test: $m" > /dev/kmsg
    fi
}

function title2() {
    local title=${1:-`basename $0`}
    echo -e "${YELLOW}#############################################${BLACK}"
    echo -e "${YELLOW}# TEST $title${BLACK}"
    echo -e "${YELLOW}#############################################${BLACK}"
    kmsg "************** TEST $title **************"
}

function reset_tc() {
    local nic1="$1"
    tc qdisc del dev $nic1 ingress >/dev/null 2>&1  || true
    tc qdisc add dev $nic1 ingress
}

function reset_tc_nic() {
    local nic1="$1"
    if [ "$backport_centos_7_2" = 1 ]; then
        : hw-tc-offload does not exists
    else
        ethtool -K $nic1 hw-tc-offload on
    fi
    reset_tc $nic1
}

function warn() {
    echo -e "${YELLOW}WARNING: $@$BLACK"
}

# print error and exit
function fail() {
    local m=${@:-Failed}
    TEST_FAILED=1
    echo -e "${RED}ERROR: $m$BLACK"
    kmsg "ERROR: $m"
    wait
    exit 1
}

function err() {
    local m=${@:-Failed}
    TEST_FAILED=1
    echo -e "${RED}ERROR: $m$BLACK"
    kmsg "ERROR: $m"
}

function success() {
    local m=${@:-OK}
    echo -e "$GREEN$m$BLACK"
    kmsg $m
}

function title() {
    echo -e "$BLUE* $@$BLACK"
    kmsg $@
}

function bring_up_reps() {
    ip link | grep DOWN | grep ens.*_[0-9] | cut -d: -f2 | xargs -I {} ip link set dev {} up
    if [ "$backport_centos_7_2" = 1 ]; then
        ip link | grep DOWN | grep eth[0-9] | cut -d: -f2 | xargs -I {} ip link set dev {} up
    fi
}

function switch_mode() {
    local extra="$2"
    echo "Change eswitch ($PCI) mode to $1 $extra"
    if [ "$backport_centos_7_2" = 1 ]; then
        echo $1 > /sys/kernel/debug/mlx5/$PCI/compat/mode
        return
    fi
    echo -n "Old mode: "
    devlink dev eswitch show pci/$PCI
    devlink dev eswitch set pci/$PCI mode $1 $extra || fail "Failed to set mode $1"
    echo -n "New mode: "
    devlink dev eswitch show pci/$PCI
    if [ "$1" = "switchdev" ]; then
        sleep 2 # wait for interfaces
        bring_up_reps
    fi
}

function switch_mode_legacy() {
    switch_mode legacy "$1"
}

function switch_mode_switchdev() {
    switch_mode switchdev "$1"
}

function get_eswitch_mode() {
    if [ "$backport_centos_7_2" = 1 ]; then
        cat /sys/kernel/debug/mlx5/$PCI/compat/mode
    else
        devlink dev eswitch show pci/$PCI | grep -o "\bmode [a-z]\+" | awk {'print $2'}
    fi
}

function get_eswitch_inline_mode() {
    if [ "$backport_centos_7_2" = 1 ]; then
        cat /sys/kernel/debug/mlx5/$PCI/compat/inline
    else
        devlink dev eswitch show pci/$PCI | grep -o "\binline-mode [a-z]\+" | awk {'print $2'}
    fi
}

function set_eswitch_inline_mode() {
    if [ "$backport_centos_7_2" = 1 ]; then
        echo $1 > /sys/kernel/debug/mlx5/$PCI/compat/inline
    else
        devlink dev eswitch set pci/$PCI inline-mode $1
    fi
}

function enable_switchdev() {
    unbind_vfs
    switch_mode_switchdev
}

function enable_switchdev_if_no_rep() {
    local rep=$1

    if [ ! -e /sys/class/net/$rep ]; then
        enable_switchdev
    fi
}

function set_macs() {
    local count=$1 # optional
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

        local a="REP$vf"
        local b=${!a}
        if [ -n "$b" ]; then
            if [ -e /sys/devices/virtual/net/$b ]; then
                echo $b
                return
            fi
            echo "Cannot find rep index $vf" >/dev/stderr
            exit 1
        fi

	if [ -z "$id" ]; then
	    echo "Cannot get switch id for $NIC" >/dev/stderr
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

function get_test_time_elapsed() {
    now=`date +"%s"`
    sec=`echo $now - $_check_start_ts + 1 | bc`
    echo $sec
}

function check_kasan() {
    now=`date +"%s"`
    sec=`echo $now - $_check_start_ts + 1 | bc`
    a=`journalctl --since="$sec seconds ago" | grep KASAN || true`
    if [ "$a" != "" ]; then
        err "$a"
        return 1
    fi
    return 0
}

function check_for_errors_log() {
    sec=`get_test_time_elapsed`
    look="health compromised|firmware internal error|assert_var|Call Trace:|DEADLOCK|possible circular locking"
    a=`journalctl --since="$sec seconds ago" | grep -E -i "$look" || true`
    if [ "$a" != "" ]; then
        err "$a"
        return 1
    fi
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
    a=`journalctl -n20 --since="$sec seconds ago" | grep syndrome || true`
    if [ "$a" != "" ]; then
        err "$a"
        return 1
    fi
    return 0
}

function expect_syndrome() {
    local expected="$1"
    # avoid same time as start_check_syndrome
    sleep 1
    now=`date +"%s"`
    sec=`echo $now - $_check_syndrome_start + 1 | bc`
    a=`journalctl -n20 --since="$sec seconds ago" | grep syndrome | grep -v $expected || true`
    if [ "$a" != "" ]; then
        err "$a"
        return 1
    fi
    return 0
}

function del_all_bridges() {
    ovs-vsctl list-br | xargs -r -l ovs-vsctl del-br 2>/dev/null
}

function stop_openvswitch() {
    service openvswitch stop
    sleep 1
    killall ovs-vswitchd ovsdb-server 2>/dev/null || true
    sleep 1
}

function start_clean_openvswitch() {
    stop_openvswitch
    service openvswitch start
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
    set +e
    check_for_errors_log
    if [ $TEST_FAILED == 0 ]; then
        success "TEST PASSED"
    else
        fail "TEST FAILED"
    fi
}

function not_relevant_for_cx5() {
    if [ "$DEVICE_IS_CX5" = 1 ]; then
        echo "Test not relevant for ConnectX-5"
        exit 0
    fi
}

function not_relevant_for_cx4() {
    if [ "$DEVICE_IS_CX4" = 1 ]; then
        echo "Test not relevant for ConnectX-4"
        exit 0
    fi
}


# load config if exists
if [ -n "$CONFIG" ]; then
    if [ -f "$CONFIG" ]; then
        echo "Loading config $CONFIG"
        . $CONFIG
    elif [ -f "$DIR/$CONFIG" ]; then
        echo "Loading config $DIR/$CONFIG"
        . $DIR/$CONFIG
    else
        warn "Config $CONFIG not found"
    fi
fi

### main
title2 `basename $0`
__setup_common
start_test_timestamp
