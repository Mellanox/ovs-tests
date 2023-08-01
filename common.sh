#!/bin/bash

__argv0=$0
if [ "$__argv0" == "-bash" -o "$__argv0" == "/bin/bash" ]; then
    __argv0='.'
fi
TESTNAME=`basename $__argv0`
TESTDIR=$(cd `dirname $__argv0` ; pwd)
DIR=$(cd "$(dirname ${BASH_SOURCE[0]})" &>/dev/null && pwd)
SET_MACS="$DIR/set-macs.sh"

COLOR0="\033["
NOCOLOR="\033[0;0m"
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
BLUE="\033[0;34m"
BLUE_BOLD="\033[0;94m"

# global var to set if test fails. should change to error but never back to
# success.
TEST_FAILED=0
# global var to use for last error msg. like errno and %m.
ERRMSG=""

VENDOR_MELLANOX="0x15b3"

<<EOT
#define PCI_DEVICE_ID_MELLANOX_CONNECTX3        0x1003
#define PCI_DEVICE_ID_MELLANOX_CONNECTX3_PRO    0x1007
#define PCI_DEVICE_ID_MELLANOX_CONNECTIB        0x1011
#define PCI_DEVICE_ID_MELLANOX_CONNECTX4        0x1013
#define PCI_DEVICE_ID_MELLANOX_CONNECTX4_LX     0x1015

    { PCI_VDEVICE(MELLANOX, 0x1011) },                  /* Connect-IB */
    { PCI_VDEVICE(MELLANOX, 0x1012), MLX5_PCI_DEV_IS_VF},       /* Connect-IB VF */
    { PCI_VDEVICE(MELLANOX, 0x1013) },                  /* ConnectX-4 */
    { PCI_VDEVICE(MELLANOX, 0x1014), MLX5_PCI_DEV_IS_VF},       /* ConnectX-4 VF */
    { PCI_VDEVICE(MELLANOX, 0x1015) },                  /* ConnectX-4LX */

        { PCI_VDEVICE(MELLANOX, 0x1016), MLX5_PCI_DEV_IS_VF},   /* ConnectX-4LX VF */
        { PCI_VDEVICE(MELLANOX, 0x1017) },                      /* ConnectX-5, PCIe 3.0 */
        { PCI_VDEVICE(MELLANOX, 0x1018), MLX5_PCI_DEV_IS_VF},   /* ConnectX-5 VF */
        { PCI_VDEVICE(MELLANOX, 0x1019) },                      /* ConnectX-5 Ex */
        { PCI_VDEVICE(MELLANOX, 0x101a), MLX5_PCI_DEV_IS_VF},   /* ConnectX-5 Ex VF */
        { PCI_VDEVICE(MELLANOX, 0x101b) },                      /* ConnectX-6 */
        { PCI_VDEVICE(MELLANOX, 0x101c), MLX5_PCI_DEV_IS_VF},   /* ConnectX-6 VF */
        { PCI_VDEVICE(MELLANOX, 0x101d) },                      /* ConnectX-6 Dx */
        { PCI_VDEVICE(MELLANOX, 0x101e), MLX5_PCI_DEV_IS_VF},   /* ConnectX Family mlx5Gen Virtual Function */
        { PCI_VDEVICE(MELLANOX, 0x101f) },                      /* ConnectX-6 LX */
        { PCI_VDEVICE(MELLANOX, 0x1021) },                      /* ConnectX-7 */
EOT

declare -A PCI_MAP
declare -A TRAFFIC_INFO

# set in __test_for_devlink_compat()
devlink_compat=0

# Special variables
__ignore_errors=0
PF_IN_NS=""


function get_mlx_iface() {
    local i
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

function __test_for_devlink_compat() {
    if [ -e /sys/kernel/debug/mlx5/$PCI/compat ]; then
        __devlink_compat_dir="/sys/kernel/debug/mlx5/\$pci/compat"
    elif [ -e /sys/class/net/$NIC/compat/devlink ]; then
        __devlink_compat_dir="/sys/class/net/\$nic/compat/devlink"
    fi
    if [ -n "$DEVLINK_COMPAT" ]; then
        devlink_compat=$DEVLINK_COMPAT
    elif devlink dev param show pci/$PCI name flow_steering_mode &>/dev/null ; then
        return
    else
        devlink_compat=${DEVLINK_COMPAT:-1}
    fi
    log "Using devlink compat $devlink_compat"
}

function get_nic_fw() {
    ethtool -i $1 | grep firmware-version | awk {'print $2'}
}

function get_rx_bytes() {
    ethtool -S $1 | grep -E 'rx_bytes_phy|vport_rx_bytes' | awk {'print $2'} | tail -1
}

function get_tx_bytes() {
    ethtool -S $1 | grep -E 'tx_bytes_phy|vport_tx_bytes' | awk {'print $2'} | tail -1
}

function get_rx_pkts() {
    ethtool -S $1 | grep -E 'rx_packets_phy|vport_rx_packets' | awk {'print $2'} | tail -1
}

function get_tx_pkts() {
    ethtool -S $1 | grep -E 'tx_packets_phy|vport_tx_packets' | awk {'print $2'} | tail -1
}

function get_tx_pkts_ns() {
    local ns=$1
    local dev=$2

    ip netns exec $ns cat /sys/class/net/$dev/statistics/tx_packets
}

function get_rx_pkts_ns() {
    local ns=$1
    local dev=$2

    ip netns exec $ns cat /sys/class/net/$dev/statistics/rx_packets
}

function require_cmd() {
    local i
    for i in $@ ; do
        if ! `which $i &>/dev/null` ; then
            fail "Missing required command $i"
        fi
    done
}

function print_key_val() {
    local m=$@
    local c=$CYAN
    awk "{for (i=1; i<=NF; i+=2) print \"$c\"\$i\"$NOCOLOR\", \$(i+1)}" <<< $m | xargs echo
}

function __get_device_name() {
    device_name="NA"
    short_device_name="NA"
    local tmp=`lspci -s $PCI | cut -d\[ -f2 | tr -d ]`

    if [[ "$tmp" == *"BlueField-2"* ]]; then
        device_name="BlueField-2"
        short_device_name="bf2"
    elif [[ "$tmp" == *"BlueField-3"* ]]; then
        device_name="BlueField-3"
        short_device_name="bf3"
    elif [ -n "$tmp" ]; then
        device_name=$tmp
        short_device_name=`echo $device_name | tr "[:upper:]" "[:lower:]" | sed -e 's/connectx-/cx/' -e 's/ //g'`
        if [ "$short_device_name" == "cx5ex" ]; then
            short_device_name="cx5"
        fi
    fi
}

function __get_pci_device_name() {
    pci_device_name="NA"

    if [ "$short_device_name" == "cx5" ]; then
        pci_device_name="galil"
    elif [ "$short_device_name" == "cx6" ]; then
        pci_device_name="negev"
    elif [ "$short_device_name" == "cx6lx" ]; then
        pci_device_name="tamar"
    elif [ "$short_device_name" == "cx6dx" ]; then
        pci_device_name="arava"
    elif [ "$short_device_name" == "cx7" ]; then
        pci_device_name="carmel"
    fi
}

function check_simx() {
    if lspci -s $PCI -vvv | grep -q SimX ; then
        IS_SIMX=1
    fi
}

function is_simx() {
    [ "$IS_SIMX" == 1 ] && return 0
    return 1
}

function is_not_simx() {
    is_simx && return 1
    return 0
}

function ofed_ver_lte() {
    local ver=$1
    if ! is_ofed ; then
        return 1
    fi
    local major=`modinfo --field version mlx5_core | tr ".-" " " | awk {'print $1'}`
    local minor=`modinfo --field version mlx5_core | tr ".-" " " | awk {'print $2'}`
    local cur="${major}.$minor"
    local o=`bc <<< "$cur <= $ver"`
    if [ "$o" == 1 ]; then
        return 0
    fi
    return 1
}

function print_mlnx_ofed_version() {
    if is_ofed ; then
        # first try version field and fallback to ofed_info script.
        local ofed_version=`modinfo --field version mlx5_core`
        if [ -z "$ofed_version" ]; then
            ofed_version=`ofed_info -s 2>/dev/null | tr -d :`
        fi
        log "MLNX_OFED $ofed_version"
    fi
}

function __setup_common() {
    start_test_timestamp

    [ -f /etc/os-release ] && . /etc/os-release
    ANSI_COLOR0="$COLOR0${ANSI_COLOR}m"
    if [ -n "$PRETTY_NAME" ]; then
        kmsg $PRETTY_NAME
        echo -e "${ANSI_COLOR0}$PRETTY_NAME$NOCOLOR"
    fi
    date
    log `uname -nsrp`

    require_interfaces NIC NIC2
    require_cmd lspci ethtool tc bc jq
    fail_if_err

    sysfs_pci_device=`readlink -f /sys/class/net/$NIC/../../`
    SRIOV_NUMVFS_NIC=$sysfs_pci_device/sriov_numvfs
    sysfs_pci_device2=`readlink -f /sys/class/net/$NIC2/../../`
    SRIOV_NUMVFS_NIC2=$sysfs_pci_device2/sriov_numvfs

    PCI=$(basename `readlink /sys/class/net/$NIC/device`)
    PCI2=$(basename `readlink /sys/class/net/$NIC2/device`)
    PCI_MAP=( [$NIC]=$PCI [$NIC2]=$PCI2 )

    DEVICE=`cat /sys/class/net/$NIC/device/device`
    PCI_DEVICE_NUM=`printf '%d' $DEVICE`
    FW=`get_nic_fw $NIC`

    __get_device_name
    __get_pci_device_name
    status="NIC $NIC FW $FW PCI $PCI DEVICE $DEVICE $device_name"
    log $status

    reset_is_bf_host
    is_bf_host && . $DIR/common-bf.sh
    is_bf && . $DIR/common-bf.sh

    print_mlnx_ofed_version
    __test_for_devlink_compat

    setup_expected_steering_mode
    setup_iptables_legacy
    clear_warn_once
    kmemleak_scan_per_test && kmemleak_clear
    __set_testpmd
    set_ovs_debug_logs
    check_simx
    simx_append_log "# TEST $TESTNAME #"
}

ovs_log_path="/var/log/openvswitch/ovs-vswitchd.log"

function set_ovs_debug_logs() {
    if [ "$CLEAR_OVS_LOG" == 1 ]; then
        if [ -f $ovs_log_path ]; then
            echo > $ovs_log_path
        fi
    fi
    if [ "$ENABLE_OVS_DEBUG" != "1" ]; then
        return
    fi
    ovs_set_log_levels netdev_offload:file:DBG netdev_offload_tc:file:DBG tc:file:DBG
}

function __set_testpmd() {
    if [ -x /opt/mellanox/dpdk/bin/dpdk-testpmd ]; then
        testpmd="LD_LIBRARY_PATH=/opt/mellanox/dpdk/lib64 /opt/mellanox/dpdk/bin/dpdk-testpmd"
    else
        testpmd="$DIR/testpmd/testpmd"
    fi
}

function kmemleak_scan_per_test() {
    [ "$KMEMLEAK_SCAN_PER_TEST" == 1 ] && return 0
    return 1
}

kmemleak_sysfs="/sys/kernel/debug/kmemleak"

function kmemleak_clear() {
    [ -w $kmemleak_sysfs ] && echo clear > $kmemleak_sysfs
}

function kmemleak_scan() {
    [ ! -w $kmemleak_sysfs ] && return
    log "Initiate kmemleak scan"
    # looks like we don't get a report on first scan but doing double scan works.
    echo scan > $kmemleak_sysfs && echo scan > $kmemleak_sysfs
}

function clear_warn_once() {
    local fs="/sys/kernel/debug/clear_warn_once"
    [ -w $fs ] && echo 1 > $fs
}

function setup_iptables_legacy() {
    if [ -f /usr/sbin/iptables-legacy ]; then
        if update-alternatives --list 2>/dev/null | grep -w iptables | grep -q legacy ; then
            return
        fi
        update-alternatives --set iptables /usr/sbin/iptables-legacy
    fi
}

function set_trusted_vf_mode() {
    local nic=$1
    local pci=$(basename `readlink /sys/class/net/$nic/device`)

    mlxreg -d $pci --reg_id 0xc007 --reg_len 0x40 --indexes "0x0.31:1=1" --yes --set "0x4.0:32=0x1" || fail "Failed to set trusted vf mode"
}

function is_mlxdump_supported() {
    is_simx && return 1

    local mode=`get_flow_steering_mode $PCI`

    if [ "$mode" == "dmfs" ]; then
        return 0
    fi
    return 1
}

function get_flow_steering_mode() {
    local pci=$1

    if is_bf_host || [ "$devlink_compat" -lt 1 ]; then
        __devlink dev param show pci/$pci name flow_steering_mode | grep "runtime value" | awk {'print $NF'}
    else
        local nic=`get_pf_nic $pci`
        cat `devlink_compat_dir $nic`/steering_mode 2>/dev/null
    fi
}

function set_flow_steering_mode() {
    local pci=$1
    local mode=$2

    log "Set $mode flow steering mode on $pci"
    if is_bf_host || [ "$devlink_compat" -lt 1 ]; then
        __devlink dev param set pci/$pci name flow_steering_mode value $mode cmode runtime || fail "Failed to set $mode flow steering mode"
    else
        local nic=`get_pf_nic $pci`
        echo $mode > `devlink_compat_dir $nic`/steering_mode || fail "Failed to set $mode flow steering mode"
    fi
}

function show_current_steering_mode() {
    local pci=`get_pf_pci`
    local pci2=`get_pf_pci2`
    local mode1=`get_flow_steering_mode $pci`
    local mode2=`get_flow_steering_mode $pci2`

    # if mode is empty assume old ofed 4.6 which doesn't support steering mode.
    if [ -n "$mode1" ]; then
        log "Flow steering mode for $pci is $mode1"
        log "Flow steering mode for $pci2 is $mode2"
    fi
}

function setup_expected_steering_mode() {
    if [ -z "$STEERING_MODE" ]; then
        show_current_steering_mode
        return
    fi

    local pci=`get_pf_pci`
    local pci2=`get_pf_pci2`
    local mode1=`get_flow_steering_mode $pci`
    local mode2=`get_flow_steering_mode $pci2`

    if [ -n "$mode1" ] && [ "$mode1" != $STEERING_MODE ]; then
        config_sriov 2
        enable_legacy $NIC
        set_flow_steering_mode $pci $STEERING_MODE
    fi
    if [ -n "$mode2" ] && [ "$mode2" != $STEERING_MODE ]; then
        config_sriov 2 $NIC2
        enable_legacy $NIC2
        set_flow_steering_mode $pci2 $STEERING_MODE
    fi
    show_current_steering_mode
}

function enable_esw_multiport() {
    local nic=$NIC
    devlink dev param show pci/$PCI name esw_multiport &>/dev/null
    if [ $? -ne 0 ]; then
        return
    fi
    log "Enable multiport eswitch"
    devlink dev param set pci/$PCI name esw_multiport value 1 cmode runtime || fail "Failed to enable multiport eswitch"
}

function disable_esw_multiport() {
    local nic=$NIC
    devlink dev param show pci/$PCI name esw_multiport &>/dev/null
    if [ $? -ne 0 ]; then
        return
    fi
    log "Disable multiport eswitch"
    devlink dev param set pci/$PCI name esw_multiport value 0 cmode runtime
}

function devlink_port_eswitch_enable() {
    local port=$1
    if is_ofed ; then
        mlxdevm port function cap set $port eswitch true || err "Failed to set port $port eswitch"
    else
        ~roid/SWS/gerrit2/iproute2/devlink/devlink port function set $port eswitch enable || err "Failed to set port $port eswitch"
    fi
}

function devlink_port_show() {
    local port=$1
    if is_ofed ; then
        mlxdevm port show $port
    else
        ~roid/SWS/gerrit2/iproute2/devlink/devlink port show $port
    fi
}

function is_vf_lag_activated() {
    local rc
    for _ in `seq 10`; do
        sleep 1
        # noticed up to 10 sec on nic mode and debug kernel.
        # look for "lag map" and not "modify lag map".
        # "lag map" print is from create lag.
        # "modify lag map" print is from modify lag.
        # In later kernel only printing shared_fdb and mode.
        dmesg | grep -v -E -i "(disagrees about version of symbol|Unknown symbol)" | tail -n10 | grep "shared_fdb" | grep -v "modify lag map"
        rc=$?
        if [ $rc -eq 0 ]; then
            # wait for driver to actually create the lag and check for error.
            sleep 1
            dmesg | tail -n10 | grep -q "Failed to create LAG" && err "Failed to create lag"
            break
        fi
    done
    return $rc
}

function is_rh72_kernel() {
    local k=`uname -r`
    if [ "$k" == "3.10.0-327.el7.x86_64" ]; then
        return 0 # true
    fi
    return 1 # false
}

function __config_bonding() {
    local nic1=${1:-$NIC}
    local nic2=${2:-$NIC2}
    local mode=${3:-active-backup}
    local xmit_hash_policy=$4
    local cmd

    log "Config bonding $nic1 $nic2 mode $mode"

    if is_rh72_kernel ; then
        ip link add name bond0 type bond
        echo 100 > /sys/class/net/bond0/bonding/miimon
        echo $mode > /sys/class/net/bond0/bonding/mode
        if [ -n "$xmit_hash_policy" ]; then
            err "xmit_hash_policy not supported"
        fi
    else
        cmd="ip link add name bond0 type bond mode $mode miimon 100"
        [ -n "$xmit_hash_policy" ] && cmd+=" xmit_hash_policy $xmit_hash_policy"
        eval $cmd || fail "Failed to create bond interface"
    fi

    ip link set dev $nic1 down
    ip link set dev $nic2 down
    ip link set dev $nic1 master bond0
    local rc1=$?
    ip link set dev $nic2 master bond0
    local rc2=$?
    if [ $rc1 -ne 0 ] || [ $rc2 -ne 0 ]; then
        fail "Failed to attach devices to bond0"
        return $rc1
    fi
    ip link set dev bond0 up
    ip link set dev $nic1 up
    ip link set dev $nic2 up
    return 0
}

function config_bonding() {
    __config_bonding $@
    if ! is_vf_lag_activated ; then
        err "VF LAG not activated in the driver?"
        return 1
    fi
    reset_tc bond0
}

function clear_bonding() {
    local nic1=${1:-$NIC}
    local nic2=${2:-$NIC2}
    log "Clear bonding"
    ip link del bond0 &>/dev/null
    ip link set dev $nic1 nomaster &>/dev/null
    ip link set dev $nic2 nomaster &>/dev/null
}

function change_slaves() {
    title "Change active lag slave from $slave1 to $slave2"

    if [[ -z "$slave1" || -z  "$slave2" || -z "$remote_active" ]]; then
        err "change_slaves: Missing variables"
        return
    fi

    local tmpslave=$slave1
    slave1=$slave2
    slave2=$tmpslave
    ifconfig $tmpslave down

    if [ "$B2B" == 1 ]; then
        if [ "$remote_active" == $REMOTE_NIC ]; then
            remote_active=$REMOTE_NIC2
        else
            remote_active=$REMOTE_NIC
        fi
        on_remote "echo $remote_active > /sys/class/net/bond0/bonding/active_slave"
    fi

    sleep 2
    ifconfig $tmpslave up
}

function remote_disable_sriov() {
    local nic1=$REMOTE_NIC
    local nic2=$REMOTE_NIC2
    echo "Disabling sriov in remote server"
    on_remote_exec disable_sriov
}

function config_remote_bonding() {
    local nic1=$REMOTE_NIC
    local nic2=$REMOTE_NIC2
    local mode=${3:-active-backup}
    log "Config remote bonding $nic1 $nic2 mode $mode"
    on_remote modprobe -q bonding || fail "Remote missing module bonding"
    clear_remote_bonding
    on_remote ip link add name bond0 type bond || fail "Failed to create remote bond interface"
    on_remote "echo 100 > /sys/class/net/bond0/bonding/miimon
               echo $mode > /sys/class/net/bond0/bonding/mode
               ip link set dev $nic1 down
               ip link set dev $nic2 down
               ip link set dev $nic1 master bond0
               ip link set dev $nic2 master bond0
               ip link set dev bond0 up
               ip link set dev $nic1 up
               ip link set dev $nic2 up"
}

function clear_remote_bonding() {
    on_remote "ip link set dev $REMOTE_NIC nomaster &>/dev/null
               ip link set dev $REMOTE_NIC2 nomaster &>/dev/null
               ip link del bond0 &>/dev/null"
}

function require_mlxreg() {
    require_cmd mlxreg
}

function require_mlxdump() {
    require_cmd mlxdump
}

function require_mlxconfig() {
    require_cmd mlxconfig
}

function require_module() {
    local module
    for module in $@ ; do
        modprobe -q $module || fail "Missing module $module"
    done
}

function require_min_kernel_5() {
    local v=`uname -r | cut -d. -f1`
    if [ $v -lt 5 ]; then
        fail "Require minimum kernel 5"
    fi
}

function simx_log() {
    local ip=`ip route get 1 | grep -o "src [0-9.]*" | awk {'print $2'}`
    echo "/workspace/logs/${ip}_simx.log"
}

function cloud_fw_reset() {
    local ip=`ip route get 1 | grep -o "src [0-9.]*" | awk {'print $2'}`
    disable_sriov
    unload_modules
    /workspace/cloud_tools/cloud_firmware_reset.sh -ips $ip || err "cloud_firmware_reset failed"
    load_modules
}

function remote_bf_wrap() {
    # overridden in common-bf.sh
    on_remote "$@"
}

function remote_bf_wrap_exec() {
    # overridden in common-bf.sh
    on_remote_exec "$@"
}

function bf_wrap() {
    # overridden in common-bf.sh
    eval "$@"
}

function bf_wrap_exec() {
    # overridden in common-bf.sh
    eval "$@"
}

function is_bf() {
    lspci -s 00:00.0 2>/dev/null | grep -wq "PCI bridge: Mellanox Technologies"
}

IS_BF_HOST=""

function is_bf_host() {
    [ -n "$IS_BF_HOST" ] && return $IS_BF_HOST

    # BF NIC mode should not have BF vars.
    if [ -z "$BF_NIC" ] || [ -z "$BF_IP" ]; then
        IS_BF_HOST=1
        return 1
    fi

    # Same $PCI could appear in arm so return if arm.
    if lspci -s 00:00.0 2>/dev/null | grep -wq "PCI bridge: Mellanox Technologies"; then
        IS_BF_HOST=1
        return 1
    fi

    lspci -s $PCI 2>/dev/null | grep -wq "Mellanox .* BlueField.* integrated"
    IS_BF_HOST=$?
    return $IS_BF_HOST
}

function reset_is_bf_host() {
    IS_BF_HOST=""
}

function is_ofed() {
    modprobe -q mlx_compat && return 0
    return 1
}

function is_cloud() {
    if [ -e /workspace/cloud_tools/ ]; then
        return 0 # true
    fi
    return 1 # false
}

function fw_reset() {
    log "fw reset"
    if is_cloud ; then
        cloud_fw_reset
    else
        mlxfwreset -y -d $PCI reset || err "mlxfwreset failed"
    fi
    wait_for_ifaces
    setup_expected_steering_mode
}

function fw_config() {
    log "fw config $@"
    mlxconfig -y -d $PCI set $@ || err "mlxconfig failed to set $@"
}

function fw_query_val() {
    mlxconfig -d $PCI q | grep $1 | awk {'print $2'}
}

function set_port_state() {
    local state=${1:-UP}
    title "Set $NIC port state $state"
    mlxlink -d $PCI --port_state $state &>/tmp/mlxlink.log || err "Failed to set port state\n`cat /tmp/mlxlink.log`"
}

function set_port_state_up() {
    set_port_state UP
}

function set_port_state_down() {
    set_port_state DN
}

function scp2() {
    scp -q -o ConnectTimeout=3 "$@"
}

function ssh2() {
    ssh -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=3 "$@"
    local rc=$?
    if [ $rc -eq 255 ]; then
        debug "SSH connection $1 rc 255"
    fi
    return $rc
}

# Run given code on remote server which provide all function and env vars
function on_remote_exec() {
    [ -z "$REMOTE_SERVER" ] && fail "No remote server configured"
    __on_remote_exec $REMOTE_SERVER "$@"
}

__foo_copied=()
# use a static file to avoid creating endless temp files.
__FOO="/tmp/foo.sh"
function __foo_copy() {
    if [[ "${__foo_copied[@]}" =~ $remote ]]; then
        return
    fi
    local i
    for i in _longopt _parse_help _parse_usage; do unset -f $i ; done
    declare -p PCI_MAP > $__FOO
    declare -p TRAFFIC_INFO >> $__FOO
    set | grep -Ev "^(BASH|SHELLOPTS|UID|EUID|PPID|_OVS_VSCTL|IS_BF_HOST)" >> $__FOO
    echo ". /etc/os-release" >> $__FOO
    scp2 $__FOO $remote:/tmp/
    __foo_copied+=($remote)
}

function __on_remote_exec() {
    local remote=$1
    __foo_copy
    ssh2 $remote ". $__FOO; ${@:2}"
}

function on_vm1() {
    [ -z "$NESTED_VM_IP1" ] && fail "No vm ip1 configured"
    __on_remote $NESTED_VM_IP1 "$@"
}

function on_vm2() {
    [ -z "$NESTED_VM_IP2" ] && fail "No vm ip2 configured"
    __on_remote $NESTED_VM_IP2 "$@"
}

function on_remote() {
    [ -z "$REMOTE_SERVER" ] && fail "No remote server configured"
    __on_remote $REMOTE_SERVER "$@"
}

function __on_remote() {
    local remote=$1
    ssh2 $remote "${@:2}"
}

function print_remote_test_separator() {
    local remote=$1
    local tmp="## TEST $TESTNAME REMOTE ##"
    local count=${#tmp}
    local sep=$(printf '%*s' $count | tr ' ' '#')
    __on_remote $remote "echo -e \"$sep\n$tmp\n$sep\" >> /dev/kmsg"
}

__USING_REMOTE_SERVER=0
function require_remote_server() {
    if [ -z "$REMOTE_SERVER" ]; then
        fail "Remote server is not configured"
    fi
    if [ -z "$REMOTE_NIC" ]; then
        fail "Remote nic is not configured"
    fi
    log "Remote server $REMOTE_SERVER"
    on_remote true || fail "Remote command failed"
    print_remote_test_separator $REMOTE_SERVER
    __USING_REMOTE_SERVER=1
}

function kmsg() {
    local m=$@
    if [ -w /dev/kmsg ]; then
        echo -e ":test: $m" >>/dev/kmsg
    fi
}

function title2() {
    local title=${1:-$TESTNAME}
    local tmp="## TEST $title ##"
    local count=${#tmp}
    local sep=$(printf '%*s' $count | tr ' ' '#')

    echo -e "Start test
${YELLOW}${sep}${NOCOLOR}
${YELLOW}${tmp}${NOCOLOR}
${YELLOW}${sep}${NOCOLOR}"

    kmsg "Start test
$sep
$tmp
$sep"
}

function max() {
    echo $(($1>$2?$1:$2))
}

function min() {
    echo $(($1<$2?$1:$2))
}

function ethtool_hw_tc_offload() {
    local nic="$1"
    ethtool -K $nic1 hw-tc-offload on &>/dev/null
}

function reset_tc() {
    local nic1
    for nic1 in $@ ; do
        ethtool_hw_tc_offload $nic1
        tc qdisc del dev $nic1 ingress >/dev/null 2>&1  || true
        tc qdisc add dev $nic1 $BLOCK_INDEX ingress $TC_ARG || err "Failed to add ingress qdisc to $nic1"
    done
}

function reset_tc_cacheable() {
    TC_ARG="cacheable"
    reset_tc $@
    unset TC_ARG
}

function reset_tc_block_index() {
    BLOCK_INDEX="ingress_block $1"
    shift

    reset_tc $@
    unset BLOCK_INDEX
}

function debug() {
    echo -e "${CYAN}`get_time_short` | $NOCOLOR$@"
    kmsg "DEBUG: $@"
}

function log() {
    echo $@
    kmsg $@
}

function log_once() {
    local var=$1
    shift
    [ "${!var}" != "" ] && return
    eval $var=1
    log $@
}

function warn() {
    echo -e "${YELLOW}WARNING: $@$NOCOLOR"
    kmsg "WARN: $@"
}

# print error and exit
function fail() {
    local m=${@:-Failed}
    if [ "$__ignore_errors" == "1" ]; then
        log $m
        return
    fi
    TEST_FAILED=1
    kill_all_bgs
    if [ "$m" != "TEST FAILED" ]; then
        m="ERROR: $m"
    fi
    echo -e "${RED}$m$NOCOLOR" >>/dev/stderr
    kmsg "$m"
    if [ "${FREEZE_ON_ERROR}" == "1" ]; then
        debug "Test is freeze on fail - press enter to exit"
        read
    fi
    exit 1
}

function err() {
    local m=${@:-Failed}
    if [ "$__ignore_errors" == "1" ]; then
        log $m
        return
    fi
    TEST_FAILED=1
    m="ERROR: $m"
    echo -e "${RED}$m$NOCOLOR"
    if [ "${FREEZE_ON_ERROR}" == "1" ]; then
        debug "Test is freeze on error - press enter to continue"
        read
    fi
    kmsg "$m"
}

function success() {
    local m=${@:-OK}
    echo -e "$GREEN$m$NOCOLOR"
    kmsg $m
}

function success2() {
    local m=$@
    echo -e "${GREEN}OK$NOCOLOR $m"
    kmsg OK
}

function title() {
    echo -e "$CYAN* $@$NOCOLOR"
    kmsg $@
}

function simx_append_log() {
    local simx_write_str="/workspace/simx/simx_tools/simx_write_str.py"
    [ ! -f $simx_write_str ] && return
    $simx_write_str -d $PCI -s "$*" >/dev/null
}

function __config_rep() {
    local rep=$1

    bf_wrap "ip address flush dev $rep
             ip link set dev $rep up"
}

function config_vf() {
    local ns=$1
    local vf=$2
    local rep=$3
    local ip=$4 # optional
    local mac=$5 # optional
    local prefix=24

    if [[ "$ip" == *":"* ]]; then
        # ipv6
        prefix=64
    fi

    local info=${mac:+$mac }${ip:+$ip}
    echo "[$ns] VF $vf ${info:+($info)} -> REP $rep"
    ip netns add $ns
    ${mac:+ip link set $vf address $mac}
    ip link set $vf netns $ns
    ${ip:+ip -netns $ns address replace dev $vf $ip/$prefix}
    ip -netns $ns link set $vf up

    __config_rep $rep
}

function add_vf_vlan() {
    local ns=$1
    local vf=$2
    local rep=$3
    local ip=$4
    local vlan=$5
    local mac=$6
    local vlan_proto=${7:-802.1Q}
    local prefix=24

    if [[ "$ip" == *":"* ]]; then
        # ipv6
        prefix=64
    fi

    echo "[$ns] $vf.$vlan (${mac:+$mac/}$ip) -> $rep"
    ip -netns $ns link add link $vf name $vf.$vlan type vlan protocol $vlan_proto id $vlan
    ip -netns $ns link set $vf.$vlan address $mac
    ip -netns $ns address replace dev $vf.$vlan $ip/$prefix
    ip -netns $ns link set $vf.$vlan up
}

function add_vf_qinq() {
    local ns=$1
    local vf=$2
    local rep=$3
    local ip=$4
    local vlan_outer=$5
    local vlan_inner=$6
    local mac=$7 # optional
    local prefix=24

    if [[ "$ip" == *":"* ]]; then
        # ipv6
        prefix=64
    fi

    echo "[$ns] $vf.$vlan_outer.$vlan_inner (${mac:+$mac/}$ip) -> $rep"
    ip -netns $ns link add link $vf name $vf.$vlan_outer type vlan protocol 802.1ad id $vlan_outer
    ip -netns $ns link add link $vf.$vlan_outer name $vf.$vlan_outer.$vlan_inner type vlan id $vlan_inner
    ${mac:+ip -netns $ns link set $vf.$vlan_outer.$vlan_inner address $mac}
    ip -netns $ns address replace dev $vf.$vlan_outer.$vlan_inner $ip/$prefix
    ip -netns $ns link set $vf.$vlan_outer up
    ip -netns $ns link set $vf.$vlan_outer.$vlan_inner up
}

function add_vf_mcast() {
    local ns=$1
    local dev=$2
    local ip=$3

    echo "[$ns] $dev mcast grp $ip"
    ip netns exec $ns sysctl -w net.ipv4.icmp_echo_ignore_broadcasts=0 >/dev/null
    ip -netns $ns a add dev $dev $ip/24 autojoin
    ip -netns $ns link set $dev up
}

function config_reps() {
    local want=$1
    local nic=$2

    config_sriov 0 $nic
    echo "Config $want VFs"
    time config_sriov $want $nic
    echo

    unbind_vfs $nic
    echo "Set switchdev"
    time switch_mode_switchdev $nic
    echo
}

function count_reps() {
    local want=$1
    local nic=$2

    swid=`cat /sys/class/net/$nic/phys_switch_id`
    echo "Verify by switch id $swid"
    count=`grep $swid /sys/class/net/*/phys_switch_id 2>/dev/null | wc -l`

    if [ $count != $want ]; then
        err "Found $count interfaces but expected $want"
    else
        success "Found $count interfaces"
    fi
}

# get uplink and vf reps.
function get_reps() {
    local i
    local nic=${1:-$NIC}
    local sid1=`get_sw_id $nic`
    local pn1=`get_port_name $nic`

    if [ -z "$sid1" ]; then
        echo "get_reps: Failed to get sw id for $nic" >> /dev/stderr
        return
    fi

    for i in `exec_pf_in_ns ls -1 /sys/class/net`; do
        local sid2=`get_sw_id $i`
        local pn2=`get_port_name $i`
        if [ "$pn2" != "p0" ] && [ "$pn2" != "p1" ]; then
            pn2=`get_parent_port_name $i`
        fi
        if [ "$sid1" == "$sid2" ] && [ "$pn1" == "$pn2" ]; then
            echo $i
        fi
    done
}

# get vf reps.
function __get_vf_reps() {
    local nic=$1
    # XXX: we might miss reps if not using the udev rule
    exec_pf_in_ns ls -1 /sys/class/net/ | grep ${nic}_[0-9]
}

function bring_up_reps() {
    local nic=${1:-$NIC}
    local ifs

    if ! exec_pf_in_ns test -e "/sys/class/net/$nic"; then return ; fi

    # XXX: we might miss reps if not using the udev rule
    ifs=`__get_vf_reps $nic`

    if [ -z "$ifs" ]; then
        echo "bring_up_reps: no reps for $nic to bring up"
        return
    fi

    if [ "$PF_IN_NS" != "" ]; then
        warn "TODO bring_up_reps: update ip link set up"
    fi

    local cmd="echo -n '$ifs' | xargs -I {} ip link set dev {} up"
    local c=`echo $ifs | wc -w`
    local x=`echo $c*0.6 | bc`
    echo "Bring up $c reps with timeout $x seconds"

    timeout $x sh -c "$cmd"
    if [ $? -eq 124 ]; then
        err "Timed out bringing interfaces up after $x seconds"
    fi
}

function get_vfs_count() {
    local nic=$1
    exec_pf_in_ns ls -1d /sys/class/net/$nic/device/virtfn* 2>/dev/null | wc -l
}

function get_reps_count() {
    get_reps $1 | wc -l
}

function __get_vf_reps_count() {
    __get_vf_reps $1 | wc -l
}

function wait_for_reps() {
    local i
    local nic=$1
    local count=$2
    local reps=0
    local found=0

    if [ "$count" == 0 ]; then return ; fi
    if ! exec_pf_in_ns test -e "/sys/class/net/$nic"; then return ; fi

    for i in `seq 4`; do
        reps=`__get_vf_reps_count $nic`
        if [ "$reps" = "$count" ]; then
            found=1
            break
        fi
        sleep 1
    done
    [ "$found" == 0 ] && warn "Found $reps reps but expected $count reps"
}

function devlink_compat_dir() {
    local nic=$1
    local pci=$(basename `readlink /sys/class/net/$nic/device` 2>/dev/null)
    local compat=`eval echo "$__devlink_compat_dir"`
    if [ -z "$compat" ] || [ ! -d $compat ]; then
        fail "Cannot get devlink compat dir"
    fi
    echo $compat
}

function wait_switch_mode_compat() {
    local nic=$1
    local mode=$2
    local vf_count=$3
    local count
    local tmp
    local i

    sleep 3

    count=`echo $vf_count/1.5 | bc`
    if [ $count -lt 20 ]; then
        count=20
    fi

    for i in `seq $count`; do
        tmp=$(cat `devlink_compat_dir $nic`/mode 2>/dev/null)
        if [ $? -eq 0 ]; then
           break
        fi
        sleep 1
    done

    if [ "$mode" != "$tmp" ]; then
        fail "Failed to set mode $mode"
    fi
}

function __devlink() {
    bf_wrap $(get_exec_pf_in_ns) devlink $@
}

function switch_mode() {
    local mode=$1
    local nic=${2:-$NIC}
    local pci=${PCI_MAP[$nic]}
    local extra="$extra_mode"
    local vf_count=`get_vfs_count $nic`

    local old_mode=`get_eswitch_mode $nic`
    if [ "$old_mode" == "$mode" ]; then
        log "E-Switch mode for $nic is $mode"
        if [ "$mode" == "switchdev" ]; then
            wait_for_reps $nic $vf_count
        fi
        return
    fi

    log "Change $nic eswitch ($pci) mode to $mode $extra"

    if [ "$devlink_compat" = 1 ]; then
        local tmp=$(cat `devlink_compat_dir $nic`/mode)
        if [ "$mode" != "$tmp" ]; then
            echo $mode > `devlink_compat_dir $nic`/mode || fail "Failed to set mode $mode"
            wait_switch_mode_compat $nic $mode $vf_count
        fi
    else
        __devlink dev eswitch set pci/$pci mode $mode $extra || fail "Failed to set mode $mode"
    fi

    if [ "$mode" == "switchdev" ]; then
        wait_for_reps $nic $vf_count
        bring_up_reps $nic
    fi

    wait_for_ifaces
}

function switch_mode_legacy() {
    switch_mode legacy $1
}

function switch_mode_switchdev() {
    switch_mode switchdev $1
}

function get_eswitch_mode() {
    local nic=${1:-$NIC}

    if [ "$devlink_compat" = 1 ]; then
        cat `devlink_compat_dir $nic`/mode 2>/dev/null
    else
        local pci=${PCI_MAP[$nic]}
        __devlink dev eswitch show pci/$pci 2>/dev/null | grep -o " mode [a-z]\+" | awk {'print $2'}
    fi
}

function get_eswitch_inline_mode() {
    if [ "$devlink_compat" = 1 ]; then
        cat `devlink_compat_dir $NIC`/inline
    else
        devlink dev eswitch show pci/$PCI | grep -o "\binline-mode [a-z]\+" | awk {'print $2'}
    fi
}

function set_eswitch_inline_mode() {
    if [ "$devlink_compat" = 1 ]; then
        echo $1 > `devlink_compat_dir $NIC`/inline
    else
        devlink dev eswitch set pci/$PCI inline-mode $1
    fi
}

function set_eswitch_inline_mode_transport() {
    if [ "$short_device_name" == "cx4lx" ]; then
        local mode=`get_eswitch_inline_mode`
        test "$mode" != "transport" && (set_eswitch_inline_mode transport || err "Failed to set inline mode transport")
    fi
}

function get_eswitch_encap() {
    if [ "$devlink_compat" = 1 ]; then
        cat `devlink_compat_dir $NIC`/encap
    else
        devlink dev eswitch show pci/$PCI | grep -o "\bencap-mode [a-z]\+" | awk {'print $2'}
    fi
}

function set_eswitch_encap() {
    local val="$1"

    if [ "$devlink_compat" = 1 ]; then
        if [ "$val" = "disable" ]; then
            val="none"
        elif [ "$val" = "enable" ]; then
            val="basic"
        fi
        echo $val > `devlink_compat_dir $NIC`/encap || err "Failed to set encap"
    else
        devlink dev eswitch set pci/$PCI encap $val || err "Failed to set encap"
    fi
}

function require_interfaces() {
    local i
    local net
    for i in $@; do
        net=${!i}
        [ -z $net ] && fail "Var $i is empty"

        if is_bf_host; then
            on_bf_exec "[ -e /sys/class/net/$net ]" && continue
        fi

        [ ! -e /sys/class/net/$net ] && fail "Cannot find interface $net"
    done
}

function enable_switchdev() {
    if is_bf_host; then
        warn "Changing eswitch mode to switchdev is not supported over bf host"
        return
    fi

    local nic=${1:-$NIC}
    unbind_vfs $nic
    switch_mode_switchdev $nic
}

function enable_legacy() {
    if is_bf_host; then
        warn "Changing eswitch mode to legacy is not supported over bf host"
        return
    fi

    local nic=${1:-$NIC}
    unbind_vfs $nic
    switch_mode_legacy $nic
}

function set_vport_match_legacy() {
    echo "Set vport match legacy"
    if [ "$devlink_compat" -ge 1 ]; then
        echo "legacy" > /sys/class/net/$NIC/compat/devlink/vport_match_mode || err "Failed to set vport match mode legacy"
    else
        devlink dev param set pci/$PCI name esw_port_metadata value false \
            cmode runtime || err "Failed to set esw_port_metadata to false"
    fi
}

function set_vport_match_metadata() {
    echo "Set vport match metadata"
    if [ "$devlink_compat" -ge 1 ]; then
        echo "metadata" > /sys/class/net/$NIC/compat/devlink/vport_match_mode || err "Failed to set vport match mode metadata"
    else
        devlink dev param set pci/$PCI name esw_port_metadata value true \
            cmode runtime || err "Failed to set esw_port_metadata to true"
    fi
}

function set_steering_sw() {
    set_flow_steering_mode $NIC smfs
}

function set_steering_fw() {
    set_flow_steering_mode $NIC dmfs
}

function config_sriov() {
    local num=${1:-2}
    local nic=${2:-$NIC}
    local numvfs_sysfs=""

    if [ "$nic" == "$NIC" ]; then
        numvfs_sysfs=$SRIOV_NUMVFS_NIC
    elif [ "$nic" == "$NIC2" ]; then
        numvfs_sysfs=$SRIOV_NUMVFS_NIC2
    fi

    [ -z "$numvfs_sysfs" ] && fail "Invalid numvfs sysfs for $nic"
    [ ! -e "$numvfs_sysfs" ] && fail "Cannot find numvfs sysfs for $nic"

    local cur=`cat $numvfs_sysfs`
    if [ $cur -eq $num ]; then
        return
    fi

    log "Config $num VFs for $nic"
    exec_pf_in_ns echo 0 > $numvfs_sysfs
    exec_pf_in_ns echo $num > $numvfs_sysfs || fail "Failed to config $num VFs on $nic"
    sleep 0.5
    udevadm trigger -c add -s net &>/dev/null
}

function disable_sriov() {
    # a feature in the driver let user set eswitch mode even if sriov is not enabled.
    # then to go back to nic mode need to enable and disable sriov again.
    # another feature is disabling sriov doesn't affect eswitch mode and we could stay in
    # offloads mode.

    # make sure in legacy mode
    enable_legacy $NIC
    enable_legacy $NIC2

    # In old kernels/mlnx ofed versions user could be in eswitch mode while sriov disabled
    # and the only way to get back to nic mode is enable and disable sriov.
    # In those kernels devlink eswitch mode fail if never changed mode
    # or reports switchdev/legacy and user can't tell if nic mode.
    if ofed_ver_lte 5.7; then
        local mode=`get_eswitch_mode 2>/dev/null`
        if [ "$mode" != "" ]; then
            config_sriov 2 $NIC
            config_sriov 2 $NIC2
        fi
    fi

    # disable sriov
    config_sriov 0 $NIC
    config_sriov 0 $NIC2
}

function enable_sriov() {
    config_sriov 2 $NIC
    config_sriov 2 $NIC2
}

function set_macs() {
    local count=$1 # optional
    $SET_MACS $NIC $count
}

function get_vf_pci() {
    local vf=${1:-$VF}

    echo $(basename `readlink /sys/class/net/${vf}/device`)
}

function get_pf_pci() {
    local pci=$PCI

    if is_bf || is_bf_host; then
        pci=$BF_PCI
    fi

    echo "$pci"
}

function get_pf_pci2() {
    local pci=$PCI2

    if is_bf || is_bf_host; then
        pci=$BF_PCI2
    fi

    echo "$pci"
}

function get_pf_nic() {
    local pci=$1

    if [ "$pci" == "$PCI" ]; then
        echo $NIC
    elif [ "$pci" == "$PCI2" ]; then
        echo $NIC2
    fi
}

function unbind_vfs() {
    local nics=${@:-$NIC}
    local vfpci
    local nic
    local i

    for nic in $nics; do
        local sysfs="/sys/bus/pci/devices/${PCI_MAP[$nic]}"

        for i in `ls -1d $sysfs/virt* 2>/dev/null`; do
            vfpci=$(basename `readlink $i`)
            if [ -e /sys/bus/pci/drivers/mlx5_core/$vfpci ]; then
                log_once __once_unbind_vfs "Unbind vfs of $nic"
                exec_pf_in_ns echo $vfpci > /sys/bus/pci/drivers/mlx5_core/unbind
            fi
        done
        unset __once_unbind_vfs
    done
}

function get_bound_vfs_count() {
    local nic=$1
    exec_pf_in_ns ls -1 /sys/class/net/*/device/physfn/net/$nic 2>/dev/null | wc -l
}

function wait_for_vfs() {
    local nic=$1
    local vfs=0
    local cmax=`get_vfs_count $nic`
    local i

    for i in `seq 10`; do
        vfs=`get_bound_vfs_count $nic`
        if [ "$vfs" = "$count" ]; then
            break
        fi
        sleep 1
    done
}

function bind_vfs() {
    local nics=${@:-$NIC}
    local i vfpci
    local nic
    local err=0

    for nic in $nics; do
        local sysfs="/sys/bus/pci/devices/${PCI_MAP[$nic]}"

        for i in `ls -1d $sysfs/virt*`; do
            vfpci=$(basename `readlink $i`)
            if [ ! -e /sys/bus/pci/drivers/mlx5_core/$vfpci ]; then
                log_once __once_bind_vfs "Bind vfs of $nic"
                exec_pf_in_ns echo $vfpci > /sys/bus/pci/drivers/mlx5_core/bind
                if [ $? -ne 0 ]; then
                    log "Cannot bind VF $vfpci"
                    err=1
                fi
            fi
        done
        unset __once_bind_vfs

        # wait for vfs if there isn't an error.
        if [ $err -eq 0 ]; then
            wait_for_vfs $nic
            udevadm settle # wait for udev renaming after bind
        fi
    done

    return $err
}

function get_exec_pf_in_ns() {
    get_exec_ns $PF_IN_NS
}

function exec_pf_in_ns() {
    local exec_ns=`get_exec_pf_in_ns`
    $exec_ns $@
}

function get_sw_id() {
    exec_pf_in_ns cat /sys/class/net/$1/phys_switch_id 2>/dev/null
}

function get_port_name() {
    exec_pf_in_ns cat /sys/class/net/$1/phys_port_name 2>/dev/null
}

function get_parent_port_name() {
    local a=`exec_pf_in_ns cat /sys/class/net/$1/phys_port_name 2>/dev/null`
    a=${a%vf*}
    a=${a//pf}
    ((a&=0x7))
    a="p$a"
    echo $a
}

function get_vf() {
    local vfn=$1
    local nic=${2:-$NIC}
    if [ -a /sys/class/net/$nic/device/virtfn$vfn/net ]; then
        echo `ls /sys/class/net/$nic/device/virtfn$vfn/net/`
    else
        fail "Cannot find vf $vfn of $nic"
    fi
}

function get_rep() {
    local i
    local vf=$1
    local id2
    local count=0
    local nic=${2:-$NIC}
    local id=`get_sw_id $nic`
    local pn=`get_port_name $nic`
    local pn2

    local b="${nic}_$vf"

    if [ -e /sys/class/net/$b ]; then
        echo $b
        return
    fi

    if [ -z "$id" ]; then
        fail "Cannot find rep index $vf. Cannot get switch id for $nic"
    fi

    for i in `ls -1 /sys/class/net`; do
        if [ $i == $nic ]; then continue ; fi

        id2=`get_sw_id $i`
        if [ "$id" != "$id2" ]; then continue ; fi

        pn2=`get_port_name $i`
        if [ "$pn2" == "p0" -o "$pn2" == "p1" ]; then continue ; fi

        pn2=`get_parent_port_name $i`
        if [ "$pn" = "$pn2" ]; then
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

function get_time() {
    date +"%s"
}

function get_date_time() {
    date +"%Y-%m-%d %H:%M:%S"
}

function get_time_short() {
    date +"%H:%M:%S"
}

function get_ms_time() {
    echo $(($(date +%s%N)/1000000))
}

function start_test_timestamp() {
    # sleep to get a unique timestamp
    sleep 1
    _check_start_ts=`date +"%s"`
    _check_start_ts_full=`get_date_time`
}

function get_test_time_elapsed() {
    local now=`date +"%s"`
    local sec=`echo $now - $_check_start_ts + 1 | bc`
    echo $sec
}

function convertsecs() {
    local t=$1 h m s o=""
    ((h=$t/3600))
    ((m=($t%3600)/60))
    ((s=$t%60))
    [ "$h" != "0" ] && o+="${h}h"
    [ "$m" != "0" ] && o+="${m}m"
    [ "$s" != "0" ] && o+="${s}s"
    echo $o
}

function get_test_time_elapsed_human() {
    convertsecs `get_test_time_elapsed`
}

function journalctl_for_test() {
    local since=${1:-$_check_start_ts_full}
    journalctl --since="$since"
}

function check_kasan() {
    local a=`journalctl_for_test | grep KASAN || true`
    if [ "$a" != "" ]; then
        err "Detected KASAN errors in the log"
        echo "$a"
        return 1
    fi
    return 0
}

function check_simx_errors() {
    local log=`simx_log`
    [ ! -f $log ] && return
    local linenum=`grep -n "# TEST $TESTNAME #" $log | tail -1 | cut -d: -f1`
    [ -z "$linenum" ] && return
    local p='$p'
    local out=`sed -n "$linenum,$p" $log | uniq`

    local look="ERR|FATAL"
    local filter=""
    local filter_warn="assertion failed: D0:P[0-9]:F0 flow index \(.*\) doesn't exist in table ID \(0x5\)"

    filter+="$filter_warn"

    if [ -n "$__expected_error_msgs" ]; then
        filter+="$__expected_error_msgs"
    fi

    local a=`echo "$out" | grep -E "$look" | grep -E -i "$filter_warn"`
    if [ "$a" != "" ]; then
        warn "Detected known issues in simx log"
        echo "$a"
    fi

    local a=`echo "$out" | grep -E "$look" | grep -v -E -i "$filter"`
    if [ "$a" != "" ]; then
        err "Detected errors in simx log"
        echo "$a"
    fi
}

function add_expected_err_for_kernel_issue() {
    local kernel=$1
    local issue_id=$2
    local message=$3

    if [[ `uname -r` != "$kernel" ]]; then
        return
    fi

    add_expected_error_for_issue $issue_id $message
}

function add_expected_error_for_issue() {
    local issue_id=$1
    local message=$2

    redmine_info $issue_id

    if redmine_bug_is_open ; then
        add_expected_error_msg $message
    fi
}

function dump_fw_basic_debug() {
    [ -z "$DEVTESTS_LOGDIR" ] && return
    [ -z "$DEVTESTS_STAMP" ] && return
    [ "$pci_device_name" == "NA" ] && return

    local basic_debug="/mswg/projects/fw/fw_ver/hca_fw_tools/basic_debug_wrapper_${pci_device_name}.sh"
    [ ! -e $basic_debug ] && return

    local fw_errs="firmware internal error|assert_var|\
Command completion arrived after timeout|Error cqe|failed reclaiming pages"
    local a=`journalctl_for_test | grep -E -i "$fw_errs" || true`
    if [ "$a" == "" ]; then
        return
    fi

    local logdir="$DEVTESTS_LOGDIR/$TESTNAME"
    log "Dump fw debug to $logdir/"
    [ ! -e $logdir ] && mkdir $logdir
    [ ! -e $logdir ] && return

    log "Save dmesg"
    dmesg -T > $logdir/dmesg.txt

    log "Save basic debug $pci_device_name"
    $basic_debug &> $logdir/basic_debug_${pci_device_name}.txt

    local dump1="$logdir/mst_dump1.txt"
    local dump2="$logdir/mst_dump2.txt"
    local dump3="$logdir/mst_dump3.txt"
    local i

    log "Save mst dumps"
    for i in $dump1 $dump2 $dump3; do
        mstdump $PCI &> $i
    done

    local out2="/swgwork/charliemb/tmp/devtests/$DEVTESTS_STAMP"
    [ ! -e $out2 ] && mkdir -p $out2
    [ -e $out2 ] && cp -r $logdir $out2
}

__expected_error_msgs=""
function add_expected_error_msg() {
    local m=$1
    __expected_error_msgs+="|$m"
}

function check_for_errors_log() {
    journalctl --sync &>/dev/null || sleep 0.5
    local since=$1
    local rc=0
    local look="DEADLOCK|possible circular locking|possible recursive locking|\
WARNING:| RIP:| BUG:|refcount > 1|refcount_t|segfault|in_atomic|hw csum failure|\
list_del corruption|which is not allocated|Objects remaining|assertion failed|\
Slab cache still has objects|Unknown object at|\
warning: consoletype is now deprecated|warning: use tty|\
kfree for unknown address|UBSAN|KASAN"
    local memleak="new suspected memory leaks"
    local memtrack="memtrack_report: Summary: .* leak\(s\) detected"
    local mlx5_errs="mlx5_core .* err |mlx5_core .* failed |syndrome|health compromised|wait_func_handle_exec_timeout|\
Can't enable single FDB mode"
    local br_errs="Packet reformat .* is not supported"
    local fw_errs="firmware internal error|assert_var|\
Command completion arrived after timeout|Error cqe|failed reclaiming pages"
    local ovs_errs="Kernel flower acknowledgment does not match request"
    local look_ahead="Call Trace:|Allocated by task|Freed by task"
    local look_ahead_count=12
    local filter="networkd-dispatcher|nm-dispatcher|uses legacy ethtool link settings|\
EAL: WARNING: cpu flags constant_tsc=yes nonstop_tsc=no|mlnx_interface_mgr.sh|sssd.*segfault|\
Skipping post send: QP err|memtrack_report: Summary: 0 leak\(s\) detected|\
systemd.* Requested transaction contradicts existing jobs: Resource deadlock avoided|\
failed to kill vid 0081/0|\
Spectre V2 : WARNING: Unprivileged eBPF is enabled with eIBRS on, data leaks possible via Spectre v2 BHB attacks!|\
kvm|pluto.* Warning: kernel has no audit support|\
Deprecated Driver is detected: iptables will not be maintained in a future major release and may be disabled|\
mlx5_pci_slot_reset Device state = 2 pci_status: 1. Exit, err = 0, result = 5, recovered"

    if [ -n "$__expected_error_msgs" ]; then
        filter+="$__expected_error_msgs"
    fi

    look="$look|$memtrack|$mlx5_errs|$br_errs|$fw_errs"
    local a=`journalctl_for_test $since | grep -E -i "$look" | grep -v -E -i "$filter" || true`
    local b=`journalctl_for_test $since | grep -E -A $look_ahead_count -i "$look_ahead" || true`
    if [ "$a" != "" ] || [ "$b" != "" ]; then
        err "Detected errors in the log"
        rc=1
    fi
    [ "$a" != "" ] && echo "$a"
    [ "$b" != "" ] && echo "$b"

    a=`journalctl_for_test $since | grep -E -i "$memleak" || true`
    if [ -f $kmemleak_sysfs ] && [ "$a" != "" ]; then
        # WA getting "mount.nfs" leaks sometimes in regression VM.
        cat $kmemleak_sysfs > /tmp/kmemleak.temp
        local unref_count=`cat /tmp/kmemleak.temp | grep -c "unreferenced object"`
        local mount_count=`cat /tmp/kmemleak.temp | grep -c "mount.nfs"`
        if [ $unref_count -ne $mount_count ]; then
            err "Detected $unref_count memory leaks in the log"
            echo "$a"
            rc=1
            cat $kmemleak_sysfs
        fi
    fi

    check_simx_errors
    dump_fw_basic_debug

    return $rc
}

function check_for_errors_log_remote() {
    if [ "$__USING_REMOTE_SERVER" != 1 ]; then
        return
    fi
    on_remote_exec check_for_errors_log || err "Detected errors on remote"
}

function check_for_err() {
    local look="$1"
    local a=`journalctl_for_test | grep -E -i "$look" || true`

    if [ "$a" != "" ]; then
        err "Detected errors in the log"
        echo "$a"
        return 1
    fi
    return 0
}

function ovs_conf_set() {
    local key=$1
    local val=$2
    ovs-vsctl set Open_vSwitch . other_config:$key=$val || err "Failed to set ovs other_config $key=$val"
}

function ovs_conf_remove() {
    local key=$1
    ovs-vsctl remove Open_vSwitch . other_config $key || err "Failed to remove ovs other_config $key"
}

function ovs_dump_flows() {
    local args=$@
    ovs-appctl dpctl/dump-flows $args 2>/dev/null
}

function ovs_dump_tc_flows() {
    local args=$@
    ovs-appctl dpctl/dump-flows $args type=tc 2>/dev/null
    [[ $? -ne 0 ]] && ovs-appctl dpctl/dump-flows $args type=offloaded
}

function ovs_dump_offloaded_flows() {
    local args=$@
    ovs-appctl dpctl/dump-flows $args type=offloaded 2>/dev/null
}

function ovs_dump_ovs_flows() {
    local args=$@
    ovs-appctl dpctl/dump-flows $args type=ovs 2>/dev/null
}

function ovs_clear_bridges() {
    bf_wrap "ovs-vsctl list-br | xargs -r -L 1 ovs-vsctl del-br 2>/dev/null"
}

function service_ovs() {
    local action=$1
    local ovs="openvswitch"
    if [ "$ID" == "ubuntu" ]; then
          ovs="openvswitch-switch"
    fi
    systemctl $action $ovs
}

function stop_openvswitch() {
    service_ovs stop
    sleep 1
    if pidof ovs-vswitchd &>/dev/null ; then
        killall ovs-vswitchd ovsdb-server 2>/dev/null || true
        sleep 1
    fi
}

function check_ovs_settings() {
    local a

    a=`ovs-vsctl get Open_vSwitch . other_config:hw-offload 2>/dev/null | tr -d '"'`
    if [ "$a" != "true" ]; then
        warn "OVS hw-offload is not set"
    fi

    a=`ovs-vsctl get Open_vSwitch . other_config:tc-policy 2>/dev/null | tr -d '"'`
    if [ "$a" != "" ]; then
        warn "OVS tc-policy is $a"
    fi

    a=`ovs-vsctl get Open_vSwitch . other_config:max-idle 2>/dev/null`
    if [ -n "$a" ]; then
        warn "OVS cleaning max-idle"
        ovs-vsctl remove Open_vSwitch . other_config max-idle
    fi

    __restart_ovs=0

    check_dpdk_init
    check_doca_init

    if [ "$__restart_ovs" == 1 ];then
        restart_openvswitch
    fi
}

function check_dpdk_init() {
    local force=0
    local want=""
    local dummy_pci="0000:00:00.0"
    local want_extra="-a $dummy_pci"

    if [ "${DPDK}" == 1 ]; then
        want="true"
    fi

    local init1=`ovs-vsctl get Open_vSwitch . other_config:dpdk-init 2>/dev/null | tr -d '"'`
    local extra1=`ovs-vsctl get Open_vSwitch . other_config:dpdk-extra 2>/dev/null | tr -d '"'`

    if [ "$want" == "true" ] && [ "$want_extra" != "$extra1" ]; then
        force=1
    fi

    if [ "$init1" != "$want" ] || [ "$force" == 1 ]; then
        warn "OVS reset dpdk-init=$want"
        if [ "$want" == "true" ]; then
           ovs-vsctl set Open_vSwitch . other_config:dpdk-extra="$want_extra"
           ovs-vsctl set Open_vSwitch . other_config:dpdk-init=true
        else
           ovs-vsctl remove Open_vSwitch . other_config dpdk-init
           ovs-vsctl remove Open_vSwitch . other_config dpdk-extra
        fi
        __restart_ovs=1
    fi
}

function check_doca_init() {
    local want=""

    if [ "${DOCA}" == 1 ]; then
        want="true"
    fi

    local init1=`ovs-vsctl get Open_vSwitch . other_config:doca-init 2>/dev/null | tr -d '"'`

    if [ "$init1" != "$want" ]; then
        warn "OVS reset doca-init=$want"
        if [ "$want" == "true" ]; then
           ovs-vsctl set Open_vSwitch . other_config:doca-init=true
        else
           ovs-vsctl remove Open_vSwitch . other_config doca-init
        fi
        __restart_ovs=1
    fi
}

__ovs_version_printed=0
function __print_ovs_version_once() {
    [ $__ovs_version_printed == 0 ] && __ovs_version_printed=1 && echo "[`hostname -s`] `ovs-vswitchd -V`"
}

function restart_openvswitch_nocheck() {
    __restart_ovs
}

__ovs_log_levels=""
function ovs_set_log_levels() {
    __ovs_log_levels=$@
}

function __restart_ovs() {
    bf_wrap_exec "stop_openvswitch
                  service_ovs start
                  __print_ovs_version_once"
}

function restart_openvswitch() {
    __restart_ovs
    ovs-appctl vlog/set tc:syslog:warn
    if [ "$__ovs_log_levels" != "" ]; then
        ovs-appctl vlog/set $__ovs_log_levels
        ovs-appctl vlog/disable-rate-limit
    fi
    check_ovs_settings
    sleep 1
}

__ovs_used=0

function start_clean_openvswitch() {
    if is_bf_host; then
        on_bf_exec "restart_openvswitch
                    ovs_clear_bridges"
        on_remote_bf_exec "restart_openvswitch
                           ovs_clear_bridges"
    else
        restart_openvswitch
        ovs_clear_bridges
    fi
    __ovs_used=1
}

function wait_for_ifaces() {
    local i
    local max=4

    for i in `seq $max`;do
        if [[ -e /sys/class/net/$NIC && -e /sys/class/net/$NIC2 ]] ;then
            return
        fi
        sleep 1
    done
    warn "Cannot find nic after $max seconds"
}

USE_OPENIBD=${USE_OPENIBD:-1}

function unload_modules() {
    log "Unload modules"
    if [ "$USE_OPENIBD" == "1" -a -e /etc/init.d/openibd ]; then
        service openibd force-stop || fail "Failed to stop openibd service"
    else
        local holders=`ls -1r /sys/module/mlx5_core/holders`
        modprobe -r $holders mlx5_core || fail "Failed to unload modules"
    fi
}

function load_modules() {
    log "Load modules"
    if [ "$USE_OPENIBD" == "1" -a -e /etc/init.d/openibd ]; then
        service openibd force-start || fail "Failed to start openibd service"
    else
        modprobe mlx5_core || fail "Failed to load modules"
    fi
}

function reload_modules() {
    unload_modules
    load_modules
    wait_for_ifaces

    check_kasan
    set_macs
    setup_expected_steering_mode
    echo "Reload modules done"
}

__probe_fs=""
__autoprobe=0
function disable_sriov_autoprobe() {
    __probe_fs="/sys/class/net/$NIC/device/sriov_drivers_autoprobe"
    if [ -e $__probe_fs ]; then
        __autoprobe=`cat $__probe_fs`
        echo 0 > $__probe_fs
    fi
}

function enable_sriov_autoprobe() {
    if [ -z $__probe_fs ]; then
        err "Cannot enable sriov autoprobe"
        return
    fi

    echo 1 > $__probe_fs
}

function restore_sriov_autoprobe() {
    if [ $__autoprobe == 1 ] && [ -n "$__probe_fs" ]; then
        echo 1 > $__probe_fs
    fi
}

function tc_filter() {
    eval2 tc -s filter $@
}

function tc_filter_success() {
    eval2 tc -s filter $@ && success
}

function tc_test_verbose() {
    tc_verbose="verbose"
    tc filter add dev $NIC ingress protocol arp prio 1 flower verbose \
        action drop &>/dev/null || tc_verbose=""
    tc filter del dev $NIC ingress &>/dev/null
}

function verify_in_hw() {
    local dev=$1
    local prio=$2
    tc filter show dev $dev ingress prio $prio | grep -q -w in_hw || err "rule prio $prio not in hw dev $dev"
}

function verify_not_in_hw() {
    local dev=$1
    local prio=$2
    tc filter show dev $dev ingress prio $prio | grep -q -w not_in_hw || err "rule prio $prio expected not in hw dev $dev"
}

function verify_in_hw_count() {
    local dev=$1
    local count=$2
    tc filter show dev $dev ingress | grep -q -w "in_hw_count $count" || err "rule not in hw dev $dev or expected count $count doesn't match"
}

function verify_have_traffic() {
    local pid=$1
    wait $pid
    local rc=$?
    if [[ $rc -eq 0 ]]; then
        :
    elif [[ $rc -eq 124 ]]; then
        err "Expected to see packets"
    else
        err "Tcpdump failed"
    fi
}

function verify_no_traffic() {
    local pid=$1
    wait $pid
    local rc=$?
    if [[ $rc -eq 124 ]]; then
        :
    elif [[ $rc -eq 0 ]]; then
        err "Didn't expect to see packets"
    else
        err "Tcpdump failed"
    fi
}

function verify_rate() {
    local rate=$1
    local expected_rate=$2

    if [ -z "$rate" ] || [ -z "$expected_rate" ]; then
        err "Missing rate" && return
    fi

    [ "$rate" -eq "$rate" ] 2>/dev/null
    if [ $? -ne 0 ]; then
        err "rate is not numeric"
        return
    fi

    local delta=$((100 * ($expected_rate - $rate)/$expected_rate))
    if [ ${delta#-} -gt 10 ]; then
        err "delta $delta: rate $rate is over the limit $expected_rate"
    fi
}

function verify_iperf3_bw() {
    local iperf_out_file=$1
    local rate=$2

    local proto=$(cat $iperf_out_file | jq -r ".start.test_start.protocol | select(.)")

    title "Check iperf3 $proto bandwidth"
    if [ "$proto" = "TCP" ]; then
        local bw=$(cat $iperf_out_file | jq ".end.sum_received.bits_per_second | select(.)")
    else
        # For UDP we have to combine results manually due to iperf3 ver 3.4 bug
        # that always outputs .end.sum_received.bits_per_second as 0:
        # https://github.com/esnet/iperf/issues/754
        #
        # Also, ignore last interval that is usually fraction of a second with
        # wildly varying rate.
        local bw=$(cat $iperf_out_file | jq '[.intervals[] | select(.sum.omitted == false) | .sum.bits_per_second] | .[0:-1] | add / length')
    fi

    bw=`bc <<< $bw/1000/1000`

    verify_rate $bw $rate
}

function wait_for_linkup() {
    local i
    local net=$1
    local state
    local max=12

    for i in `seq $max`; do
        state=`cat /sys/class/net/$net/operstate`
        if [ "$state" = "up" ]; then
            return
        fi
        sleep 1
    done
    warn "Link for $net is not up after $max seconds"
}

function getnet() {
    local ip=$1
    local net=$2
    which ipcalc >/dev/null || fail "Need ipcalc"
    if [ "$ID" == "ubuntu" ]; then
        echo `ipcalc -n $ip/$net | grep Network: | awk {'print $2'}`
    else
        echo `ipcalc -n $ip/$net | cut -d= -f2`/$net
    fi
}

function eval2() {
    eval $@
    local err=$?
    test $err != 0 && err "Command failed ($err): $@"
    return $err
}

function fail_if_err() {
    local m=${@:-TEST FAILED}
    if [ $TEST_FAILED != 0 ]; then
        kill_all_bgs
        check_for_errors_log
        check_for_errors_log_remote
        log "runtime: `get_test_time_elapsed_human`"
        fail $m
    fi
}

function kill_all_bgs() {
    local bgs=$(jobs -p)
    if [ -n "$bgs" ]; then
        kill $bgs 2>/dev/null
        sleep 1
        kill -9 $bgs 2>/dev/null
        log "Wait for bgs $bgs"
        wait $bgs &>/dev/null
    fi
}

function reload_driver_per_test() {
    [ "$RELOAD_DRIVER_PER_TEST" == 1 ] && return 0
    return 1
}

function dump_ovs_log() {
    local look="ERR|WARN|EMER|assertion|DBG"
    local filter="timeval|ioctl|coverage|flow create.*void|ufid 00000000-0000-0000-0000-000000000000"

    if [ -f $ovs_log_path ] && [ "$__ovs_used" == 1 ] && [ "$CLEAR_OVS_LOG" == 1 ]; then
        local a=`cat $ovs_log_path | grep -E "$look" | grep -v -E "$filter"`
        if [ "$a" != "" ]; then
            err "Detected errors in ovs log"
            echo "$a"
        fi
    fi
}

function test_done() {
    kill_all_bgs
    set +e
    reload_driver_per_test && reload_modules
    kmemleak_scan_per_test && kmemleak_scan
    check_for_errors_log
    check_for_errors_log_remote
    log "runtime: `get_test_time_elapsed_human`"
    if [ $TEST_FAILED == 0 ]; then
        success "TEST PASSED"
    else
        dump_ovs_log
        fail "TEST FAILED"
    fi
    exit $TEST_FAILED
}

function not_relevant_for_nic() {
    local nic
    for nic in $@ ; do
        if [ "$short_device_name" == "$nic" ]; then
            fail "Test not relevant for $device_name"
        fi
    done
}

function min_nic_cx6() {
    not_relevant_for_nic cx4 cx4lx cx5
}

function min_nic_cx6dx() {
    not_relevant_for_nic cx4 cx4lx cx5 cx6
}

function relevant_for_nic() {
    local nic
    for nic in $@ ; do
        if [ "$short_device_name" == "$nic" ]; then
            return
        fi
    done
    fail "Test relevant for $nic"
}

function require_fw_opt() {
    mlxconfig -d $PCI q | grep -q -w $1
    if [ "$?" != 0 ]; then
        fail "FW option $1 is not supported"
    fi
}

function require_fw_ver() {
    local minor=$1
    local subminor=$2
    local FWV=( ${FW//./ } )

    if [ ${FWV[1]} -lt $minor ]; then
        fail "FW ($FW) must be >= xx.$minor.$subminor, please upgrade"
    elif [ ${FWV[1]} -eq $minor ]; then
        if [ ${FWV[2]} -lt $subminor ]; then
            fail "FW ($FW) must be >= xx.$minor.$subminor, please upgrade"
        fi
    fi
}

function fw_ver_ge() {
    local minor=$1
    local subminor=$2
    local FWV=( ${FW//./ } )

    if [ ${FWV[1]} -gt $minor ]; then
        return 0
    elif [ ${FWV[1]} -eq $minor ]; then
        if [ ${FWV[2]} -ge $subminor ]; then
            return 0
        fi
    fi
    return 1
}

function fw_ver_lt() {
    if fw_ver_ge $@; then
        return 1
    fi
    return 0
}

function __detect_config() {
    local i
    for i in `ls -1d /sys/class/net/*`; do
        cat $i/phys_switch_id &>/dev/null || continue
        local driver=$(basename `readlink $i/device/driver`)
        [ "$driver" == "mlx5_core" ] || continue
        local port_name=`cat $i/phys_port_name 2>/dev/null`
        if [ "$port_name" == "p0" ]; then
            NIC=`basename $i`
            echo "Detected NIC=$NIC"
        elif [ "$port_name" == "p1" ]; then
            NIC2=`basename $i`
            echo "Detected NIC2=$NIC2"
        fi
        [ -n "$NIC" ] && [ -n "$NIC2" ] && break
    done
    is_bf && BF_NIC=$NIC && BF_NIC2=$NIC2
    [ -n "$NIC" ] && [ -n "$NIC2" ] && return 0
    return 1
}

function __load_config() {
    local conf

    # load config if exists
    if [ -n "$CONFIG" ]; then
        if [ -f "$CONFIG" ]; then
            conf=$CONFIG
        elif [ -f "$DIR/$CONFIG" ]; then
            conf=$DIR/$CONFIG
        else
            fail "Config $CONFIG not found"
        fi
    else
        __detect_config || fail "Missing CONFIG"
    fi

    if [ -n "$conf" ]; then
        echo "Loading config $conf"
        . $conf
    fi
}

function __trapped_int_cleanup() {
    fail "Terminate requested"
}

function __setup_clean() {
    local n
    for n in $NIC $NIC2 $VF $VF2 $REP $REP2 ; do
        if [ -e /sys/class/net/$n ]; then
            reset_tc $n
            ip address flush dev $n
            ip -6 address flush dev $n
        fi
    done
}

function warn_if_redmine_bug_is_open() {
    local i
    local issues=`head -n50 $TESTDIR/$TESTNAME | grep "^#" | grep -o "Bug SW #[0-9]\+" | cut -d"#" -f2`
    local p=0
    for i in $issues ; do
        redmine_info $i
        if redmine_bug_is_open ; then
            warn "RM $RM_STATUS: $i $RM_SUBJ"
            p=1
        fi
    done
    [ $p -eq 1 ] && sleep 2
}

# 'Closed', 'Fixed', 'External', 'Closed (External)', 'Rejected', 'Closed (Rejected)'
RM_STATUS_CLOSED=5
RM_STATUS_REJECTED=6
RM_STATUS_WONT_FIX=11
RM_STATUS_RELEASE_NOTES=14
RM_STATUS_FIXED=16
RM_STATUS_CLOSED_REJECTED=38
RM_STATUS_CLOSED_EXTERNAL=74
RM_STATUS_LIST="$RM_STATUS_CLOSED $RM_STATUS_REJECTED
                $RM_STATUS_FIXED $RM_STATUS_CLOSED_REJECTED $RM_STATUS_CLOSED_EXTERNAL"

function redmine_bug_is_open() {
    local i
    [ "$RM_STATUS_ID" = "" ] && return 1
    for i in $RM_STATUS_LIST ; do
        if [ $RM_STATUS_ID = $i ]; then
            return 1
        fi
    done
    return 0
}

function redmine_info() {
    local id=$1
    local rm_key_path='/labhome/roid/scripts/redmine/redmine_key.txt'
    [ ! -f $rm_key_path ] && return
    local key=`cat $rm_key_path 2>/dev/null`
    local url="https://redmine.mtl.com/issues/${id}.json?key=$key"
    RM_STATUS_ID=""
    RM_STATUS=""
    RM_SUBJ=""
    eval `curl -k -L -m 1 -s "$url" | python -c "from __future__ import print_function; import sys, json; i=json.load(sys.stdin)['issue']; print(\"RM_STATUS_ID=%s\nRM_STATUS=%s\nRM_SUBJ=%s\" % (json.dumps(i['status']['id']), json.dumps(i['status']['name']), json.dumps(i['subject'])))" 2>/dev/null`
    if [ -z "$RM_STATUS_ID" ]; then
        warn "Failed to fetch #$id redmine info"
    fi
}

function verify_mlxconfig_for_sf() {
    warn "Using redundant function: verify_mlxconfig_for_sf"

    # simx doesn't expose these but assumed to support.
    is_simx && return

    #First check newer config, if its enabled or not.
    local PER_PF_NUM_SF="True(1)"
    local pf_total_sf=`fw_query_val PF_TOTAL_SF`
    local per_pf_num_sf=`fw_query_val PER_PF_NUM_SF`
    if [[ $pf_total_sf != "0" && $per_pf_num_sf == $PER_PF_NUM_SF ]]; then
        return
    fi
    #Newer config is not enabled, check older config.
    local SF_BAR2_ENABLED="True(1)"
    local bar2_enable=`fw_query_val PF_BAR2_ENABLE`
    echo "PF_BAR2_ENABLE=$bar2_enable"
    if [ "$bar2_enable" != "$SF_BAR2_ENABLED" ]; then
        fail "Cannot support SF with current mlxconfig settings"
    fi
}

function get_free_memory() {
    echo $(cat /proc/meminfo | grep MemFree | sed 's/[^0-9]*//g')
}

function dmfs_dump() {
    local i
    i=0 && mlxdump -d $PCI fsdump --type FT --gvmi=$i --no_zero > /tmp/port$i || err "mlxdump failed"
}

function smfs_dump() {
    local dump=${1:-dump}
    if [ -e /sys/kernel/debug/mlx5/$PCI/steering/fdb ]; then
        cat /sys/kernel/debug/mlx5/$PCI/steering/fdb/* > /tmp/$dump || err "smfs dump failed"
    else
        cat /proc/driver/mlx5_core/smfs_dump/fdb/$PCI > /tmp/$dump || err "smfs dump failed"
    fi
}

function fw_dump() {
    local dump=$1
    local mode=`get_flow_steering_mode $PCI`
    if [ "$mode" == "smfs" ]; then
        smfs_dump $dump
    elif [ "$mode" == "dmfs" ]; then
        dmfs_dump
    fi
}

function config_remote_vxlan() {
    if [ -z "$VXLAN_ID" ] || [ -z "$REMOTE_IP" ]; then
        err "Cannot config remote vxlan"
        return
    fi
    if [ -z "$DSTPORT" ]; then
        DSTPORT=4789
    fi
    on_remote "ip link del vxlan1 &>/dev/null
               ip a flush dev $REMOTE_NIC
               ip link add vxlan1 type vxlan id $VXLAN_ID dev $REMOTE_NIC dstport $DSTPORT $VXLAN_OPTIONS
               ip a add $REMOTE_IP/24 dev $REMOTE_NIC
               ip a add $REMOTE/24 dev vxlan1
               ip l set dev vxlan1 up
               ip l set dev $REMOTE_NIC up
               tc qdisc add dev vxlan1 ingress" || err "Failed to config remote vxlan"
}

function config_remote_geneve() {
    local ext=$1
    if [ -z "$REMOTE_IP" ]; then
        err "Cannot config remote geneve"
        return
    fi

    if [ -z "$geneve_port" ]; then
        local geneve_port=6081
    fi

    local tun="external"
    local set_ip=""

    if [ "$ext" != "external" ] && [ -n "$TUN_ID" ]; then
        tun="id $TUN_ID remote $LOCAL_TUN"
        set_ip="ip a add $REMOTE/24 dev geneve1"
    fi

    on_remote "ip link del geneve1 &>/dev/null
               ip a flush dev $REMOTE_NIC
               ip link add geneve1 type geneve $tun dstport $geneve_port
               ip a add $REMOTE_IP/24 dev $REMOTE_NIC
               $set_ip
               ip l set dev geneve1 up
               ip l set dev $REMOTE_NIC up
               tc qdisc add dev geneve1 ingress" || err "Failed to config remote geneve"
}

function cleanup_remote_vxlan() {
    on_remote "ip a flush dev $REMOTE_NIC
               ip l del dev vxlan1 &>/dev/null"
}

function compile_psample() {
    psample_dir="$DIR/psample"
    test -d $psample_dir || fail "Cannot find psample $psample_dir"
    rm -fr /tmp/psample
    cp -r $psample_dir /tmp/psample
    psample_dir="/tmp/psample"
    make -C /tmp/psample || fail "Failed to compile psample in dir $psample_dir"
}

function ns_wrap() {
    local cmd=$1
    local ns=$2

    if [[ -n $ns ]]; then
        cmd="ip netns exec $ns $cmd"
    fi
    echo $cmd
}

function get_exec_ns() {
    local ns=$1
    local exec_ns

    if [ -n "$ns" ]; then
        exec_ns="ip netns exec $ns"
    fi

    echo $exec_ns
}

function is_ipv6() {
    local ip=$1

    if [[ "$ip" == *":"* ]]; then
        return 0
    fi

    return 1
}

function create_vlan_interface() {
    local parent_int=$1
    local vlan_int=$2
    local vlan_id=$3

    ip link add link $parent_int name $vlan_int type vlan id $vlan_id
}

function get_ovs_id() {
    cat /etc/openvswitch/system-id.conf 2>/dev/null || fail "Got empty ovs id"
}

function get_lag_resource_allocation_mode() {
    if echo $(fw_query_val LAG_RESOURCE_ALLOCATION) | grep 1 > /dev/null; then
        echo 1
    else
        echo 0
    fi
}

function set_lag_resource_allocation() {
    local value=$1
    title "lag_resource_allocation value to $value"
    fw_config LAG_RESOURCE_ALLOCATION=$value || fail "Cannot set lag resource allocation to $value"
    fw_reset
}

__lag_res_alloc_mode=0
__lag_res_alloc_changed=0
function enable_lag_resource_allocation_mode() {
    local current_mode=`get_lag_resource_allocation_mode`
    if [ "$current_mode" == "1" ]; then
        return
    fi
    if (( __lag_res_alloc_changed == 0 )); then
        __lag_res_alloc_mode=$current_mode
        set_lag_resource_allocation 1
        __lag_res_alloc_changed=1
    fi
}

function restore_lag_resource_allocation_mode() {
    if (( __lag_res_alloc_changed == 1 )); then
        set_lag_resource_allocation $__lag_res_alloc_mode
    fi
}

__lag_port_select_mode="hash"
__lag_port_select_mode_changed=0
function set_lag_port_select_mode() {
    if [ ! -f /sys/class/net/$NIC/compat/devlink/lag_port_select_mode ]; then
        # MLNX OFED 5.7 needs to enable a compat. verify if exists.
        return
    fi

    local mode=$1
    local current_mode=`get_lag_port_select_mode`

    if [ "$current_mode" == "$mode" ]; then
        log "Current lag port select mode is $current_mode"
        return
    fi

    if (( __lag_port_select_mode_changed == 0 )); then
        __lag_port_select_mode=$current_mode
        __lag_port_select_mode_changed=1
    fi

    log "Changing lag port select mode to $mode"
    enable_legacy &>/dev/null
    enable_legacy $NIC2 &>/dev/null
    echo $mode > /sys/class/net/$NIC/compat/devlink/lag_port_select_mode || fail "Failed to set $NIC lag_port_select_mode to $mode"
    echo $mode > /sys/class/net/$NIC2/compat/devlink/lag_port_select_mode || fail "Failed to set $NIC2 lag_port_select_mode to $mode"
}

function get_lag_port_select_mode() {
    cat /sys/class/net/$NIC/compat/devlink/lag_port_select_mode || fail "Failed to get $NIC lag_port_select_mode"
}

function restore_lag_port_select_mode() {
    if (( __lag_port_select_mode_changed == 1 )); then
        set_lag_port_select_mode $__lag_port_select_mode
    fi
}

function grace_period_after_pci_reset() {
    local sleep=70
    local output=`devlink health show pci/${PCI} reporter fw_fatal 2>/dev/null | grep -Eo "grace_period [0-9]+" | awk {'print $2'}`

    if [ -n "$output" ]; then
        local devlink_grace=$((output/1000))

        if [[ $devlink_grace -gt $sleep ]]; then
            sleep=$devlink_grace
        fi
    fi

    # the grace period should start after pci recovers.
    timeout 20 grep -m1 "health recovery succeeded" <(dmesg -W)

    echo "Waiting $sleep sec for pci reset grace period"
    sleep $sleep

}

function pci_reset() {
    echo 1 > /sys/bus/pci/devices/$PCI/reset
    grace_period_after_pci_reset
}

function enable_ftrace() {
    local ftrace_filter=$1
    echo function_graph > /sys/kernel/debug/tracing/current_tracer
    echo $ftrace_filter > /sys/kernel/debug/tracing/set_ftrace_filter
    echo 1 > /sys/kernel/debug/tracing/tracing_on
    echo > /sys/kernel/debug/tracing/trace
}

function disable_ftrace() {
    echo 0 > /sys/kernel/debug/tracing/tracing_on
}

function __test_help() {
    echo "To run a test export a config and run the test script as so:"
    echo
    echo "export CONFIG=/path/to/config.sh"
    echo "$TESTDIR/$TESTNAME"
    echo
    echo "Available exports:"
    echo
    echo "DEVLINK_COMPAT=0|1|2          - Force to use or not use ofed devlink compat."
    echo "KMEMLEAK_SCAN_PER_TEST=1      - Do kmemleak scan per test."
    echo "RELOAD_DRIVER_PER_TEST=1      - Reload driver at the end of the test."
    echo "USE_OPENIBD=1                 - Use openibd service script (i.e. MLNX OFED) to reload modules. default=1"
    echo "FREEZE_ON_ERROR=1             - Pause test on each error."
    echo "ENABLE_OVS_DEBUG=1            - Set ovs debug level."
    echo "CLEAR_OVS_LOG=1               - Clear ovs log at the start of the test."
    exit 0
}

function __common_main() {
    if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
        __test_help
    fi
    [ "$__COMMON_SH" == 1 ] && return
    __COMMON_SH=1
    if [ "X${NO_TITLE}" == "X" ]; then
        title2 $TESTNAME
    fi
    __load_config
    warn_if_redmine_bug_is_open
    trap __trapped_int_cleanup INT
    __setup_common
    __setup_clean
}

function __common_help() {
    echo "Evaluate a script as:"
    echo
    echo "bash $TESTNAME [script]"
    echo
    echo "Example: bash $TESTNAME \"enable_switchdev\""
    exit 0
}

function __common_eval() {
    if [ "$1" == "-h" ] || [ "$1" == "--help" ] || [ "$*" == "" ]; then
        __common_help
    fi
    NO_TITLE=1
    __common_main
    log "Evaluate: $@"
    eval $@
    exit $?
}

# common script executed directly. evaluate user input.
if [[ "$TESTNAME" == common* ]]; then
    __common_eval $@
fi

# script included from bash console. do nothing
if [ "$TESTNAME" == "." ]; then
    return
fi

# execute normally
__common_main $@
