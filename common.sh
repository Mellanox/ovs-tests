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

# test in __setup_common() for /sys/kernel/debug/mlx5/81:00.0/compat
devlink_compat=0


function service_ovs() {
    local ovs="openvswitch"
    local a=`systemctl show -p LoadError $ovs | grep -o DBus.Error`
    if [ "$a" = "DBus.Error" ]; then
          ovs="openvswitch-switch"
    fi
    service $ovs $1
}


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

    if [ -e /sys/kernel/debug/mlx5/$PCI/compat ]; then
        echo "devlink compat"
        devlink_compat=1
    fi

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

function require_mlxdump() {
    [[ -e /usr/bin/mlxdump ]] || fail "Missing mlxdump"
}

function require_mlxconfig() {
    [[ -e /usr/bin/mlxconfig ]] || fail "Missing mlxconfig"
}

function kmsg() {
    local m=$@
    if [ -w /dev/kmsg ]; then
        echo -e ":test: $m" >>/dev/kmsg
    fi
}

function title2() {
    local title=${1:-`basename $0`}
    echo -e "${YELLOW}#############################################${BLACK}"
    echo -e "${YELLOW}# TEST $title${BLACK}"
    echo -e "${YELLOW}#############################################${BLACK}"
    kmsg "************** TEST $title **************"
}

function ethtool_hw_tc_offload() {
    local nic="$1"
    if [ "$devlink_compat" = 1 ]; then
        : hw-tc-offload does not exists
    else
        ethtool -K $nic1 hw-tc-offload on 2>/dev/null
    fi
}

function reset_tc() {
    local nic1="$1"
    ethtool_hw_tc_offload
    tc qdisc del dev $nic1 ingress >/dev/null 2>&1  || true
    tc qdisc add dev $nic1 ingress
}

# redundant function. use reset_tc().
function reset_tc_nic() {
    reset_tc $1
}

function warn() {
    echo -e "${YELLOW}WARNING: $@$BLACK"
}

# print error and exit
function fail() {
    local m=${@:-Failed}
    TEST_FAILED=1
    echo -e "${RED}ERROR: $m$BLACK" >>/dev/stderr
    kmsg "ERROR: $m"
    wait
    exit 1
}

function err() {
    local m=${@:-Failed}
    TEST_FAILED=1
    echo -e "${RED}ERROR: $m$BLACK" >>/dev/stderr
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
    if [ "$devlink_compat" = 1 ]; then
        ip link | grep DOWN | grep eth[0-9] | cut -d: -f2 | xargs -I {} ip link set dev {} up
    fi
}

function switch_mode() {
    local nic=${2:-$NIC}
    local pci=$(basename `readlink /sys/class/net/$nic/device`)
    local extra="$extra_mode"

    echo "Change eswitch ($pci) mode to $1 $extra"
    if [ "$devlink_compat" = 1 ]; then
        echo $1 > /sys/kernel/debug/mlx5/$pci/compat/mode || fail "Failed to set mode $1"
        return
    fi
    echo -n "Old mode: "
    devlink dev eswitch show pci/$pci
    devlink dev eswitch set pci/$pci mode $1 $extra || fail "Failed to set mode $1"
    echo -n "New mode: "
    devlink dev eswitch show pci/$pci
    if [ "$1" = "switchdev" ]; then
        sleep 2 # wait for interfaces
        bring_up_reps
    fi
}

function switch_mode_legacy() {
    switch_mode legacy $1
}

function switch_mode_switchdev() {
    switch_mode switchdev $1
}

function get_eswitch_mode() {
    if [ "$devlink_compat" = 1 ]; then
        cat /sys/kernel/debug/mlx5/$PCI/compat/mode
    else
        devlink dev eswitch show pci/$PCI | grep -o "\bmode [a-z]\+" | awk {'print $2'}
    fi
}

function get_eswitch_inline_mode() {
    if [ "$devlink_compat" = 1 ]; then
        cat /sys/kernel/debug/mlx5/$PCI/compat/inline
    else
        devlink dev eswitch show pci/$PCI | grep -o "\binline-mode [a-z]\+" | awk {'print $2'}
    fi
}

function set_eswitch_inline_mode() {
    if [ "$devlink_compat" = 1 ]; then
        echo $1 > /sys/kernel/debug/mlx5/$PCI/compat/inline
    else
        devlink dev eswitch set pci/$PCI inline-mode $1
    fi
}

function require_multipath_support() {
    local m=""

    if [ "$devlink_compat" = 1 ]; then
        if [ -e /sys/kernel/debug/mlx5/$PCI/compat/multipath ]; then
            m="ok"
        fi
    else
        m=`get_multipath_mode`
    fi

    if [ "$m" == "" ]; then
        fail "Require multipath support"
    fi
}

function require_interfaces() {
    local net
    for i in $@; do
        net=${!i}
        [ -z $net ] && fail "Var $i is empty"
        [ ! -e /sys/class/net/$net ] && fail "Cannot find interface $net"
    done
}

function enable_multipath() {
    if [ "$devlink_compat" = 1 ]; then
        echo enabled > /sys/kernel/debug/mlx5/$PCI/compat/multipath
    else
        devlink dev eswitch set pci/$PCI multipath enable
    fi
}

function disable_multipath() {
    if [ "$devlink_compat" = 1 ]; then
        echo disabled > /sys/kernel/debug/mlx5/$PCI/compat/multipath
    else
        devlink dev eswitch set pci/$PCI multipath disable
    fi
}

function enable_switchdev() {
    local nic=${1:-$NIC}
    unbind_vfs $nic
    switch_mode_switchdev $nic
}

function enable_legacy() {
    local nic=${1:-$NIC}
    unbind_vfs $nic
    switch_mode_switchdev $nic
}

function get_multipath_mode() {
    if [ "$devlink_compat" = 1 ]; then
        cat /sys/kernel/debug/mlx5/$PCI/compat/multipath
    else
        devlink dev eswitch show pci/$PCI | grep -o "\bmultipath [a-z]\+" | awk {'print $2'}
    fi
}

function enable_switchdev_if_no_rep() {
    local rep=$1

    if [ ! -e /sys/class/net/$rep ]; then
        enable_switchdev
    fi
}

function config_sriov() {
    local num=$1
    local nic=${2:-$NIC}
    echo $num > /sys/class/net/$nic/device/sriov_numvfs
}

function set_macs() {
    local count=$1 # optional
    $SET_MACS $NIC $count
}

function unbind_vfs() {
    local nic=${1:-$NIC}
    for i in `ls -1d /sys/class/net/$nic/device/virt*`; do
        vfpci=$(basename `readlink $i`)
        if [ -e /sys/bus/pci/drivers/mlx5_core/$vfpci ]; then
            echo "unbind $vfpci"
            echo $vfpci > /sys/bus/pci/drivers/mlx5_core/unbind
        fi
    done
}

function bind_vfs() {
    local nic=${1:-$NIC}
    for i in `ls -1d /sys/class/net/$nic/device/virt*`; do
        vfpci=$(basename `readlink $i`)
        if [ ! -e /sys/bus/pci/drivers/mlx5_core/$vfpci ]; then
            echo "bind vf $vfpci"
            echo $vfpci > /sys/bus/pci/drivers/mlx5_core/bind
        fi
    done
    # sometimes need half a second for netdevs to appear.
    sleep 0.5
}

function get_sw_id() {
    cat /sys/class/net/$1/phys_switch_id 2>/dev/null
}

function get_vf() {
    local vfn=$1
    local nic=$2
    if [ -a /sys/class/net/$nic/device/virtfn$vfn/net ]; then
	echo `ls /sys/class/net/$nic/device/virtfn$vfn/net/`
    else 
	fail "cannot find vf $vfn of $nic"
    fi
}

function get_rep() {
	local vf=$1
	local id2
	local count=0
	local nic=${2:-$NIC}
	local id=`get_sw_id $nic`

        local b="${nic}_$vf"

	if [ -e /sys/devices/virtual/net/$b ]; then
	    echo $b
	    return
	fi

	if [ -z "$id" ]; then
	    fail "Cannot find rep index $vf. Cannot get switch id for $nic"
	fi

	VIRTUAL="/sys/devices/virtual/net"

	for i in `ls -1 $VIRTUAL`; do
	    id2=`get_sw_id $i`
	    if [ "$id" = "$id2" ]; then
		if [ "$vf" = "$count" ]; then
			echo $i
			echo "Found rep $i" >>/dev/stderr
			return
		fi
		((count=count+1))
	    fi
	done
	fail "Cannot find rep index $vf"
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
    look="health compromised|firmware internal error|assert_var|Call Trace:|DEADLOCK|possible circular locking|WARNING:|RIP:"
    a=`journalctl --since="$sec seconds ago" | grep -E -i "$look" || true`
    if [ "$a" != "" ]; then
        err "Detected errors in the log"
        echo "$a" >>/dev/stderr
        return 1
    fi
    return 0
}

function check_for_err() {
    local look="$1"
    local sec=`get_test_time_elapsed`
    local a=`journalctl --since="$sec seconds ago" | grep -E -i "$look" || true`

    if [ "$a" != "" ]; then
        err "Detected errors in the log"
        echo "$a" >>/dev/stderr
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
    a=`journalctl --since="$sec seconds ago" | grep syndrome || true`
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
    a=`journalctl --since="$sec seconds ago" | grep syndrome | grep -v $expected || true`
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
    service_ovs stop
    sleep 1
    killall ovs-vswitchd ovsdb-server 2>/dev/null || true
    sleep 1
}

function start_clean_openvswitch() {
    stop_openvswitch
    service_ovs start
    sleep 1
    del_all_bridges
}

function reload_modules() {
    if [ "$devlink_compat" = 1 ]; then
        service openibd force-restart
    else
        modprobe -r mlx5_ib mlx5_core devlink || fail "Failed to unload modules"
        modprobe -a devlink mlx5_core mlx5_ib || fail "Failed to load modules"
    fi

    a=`journalctl -n200 | grep KASAN || true`
    if [ "$a" != "" ]; then
        fail "Detected KASAN in journalctl"
    fi
    set_macs
    echo "reload modules done"
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

function __load_config() {
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

    test -n "$FORCE_VF2" && VF2=$FORCE_VF2
    test -n "$FORCE_REP2" && REP2=$FORCE_REP2
}

function __cleanup() {
    err "Terminate requested"
    exit 1
}

function __setup_clean() {
    [ "$NIC" != "" ] && ifconfig $NIC 0 && reset_tc $NIC
    [ "$VF" != "" ] && [ -e /sys/class/net/$VF ] && ifconfig $VF 0
    [ "$VF2" != "" ] && [ -e /sys/class/net/$VF2 ] && ifconfig $VF2 0
}

### main
title2 `basename $0`
start_test_timestamp
trap __cleanup INT
__load_config
__setup_common
__setup_clean
