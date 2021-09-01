#!/bin/bash

TESTNAME=`basename $0`
DIR=$(cd `dirname $0` ; pwd)
SET_MACS="$DIR/set-macs.sh"

COLOR0="\033["
NOCOLOR="\033[0;0m"
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
LIGHTBLUE="\033[0;34m"
LIGHTBLUE_BOLD="\033[0;94m"

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

# test in __setup_common()
devlink_compat=0

# Special variables
__ignore_errors=0


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
    if devlink dev param show pci/$PCI name flow_steering_mode &>/dev/null ; then
        return
    fi
    log "Using devlink compat"
    devlink_compat=1
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

function require_cmd() {
    local i
    for i in $@ ; do
        if ! `which $i &>/dev/null` ; then
            err "Missing required command $i"
        fi
    done
}

function print_key_val() {
    local m=$@
    local c=$LIGHTBLUE
    awk "{for (i=1; i<=NF; i+=2) print \"$c\"\$i\"$NOCOLOR\", \$(i+1)}" <<< $m | xargs echo
}

function __get_device_name() {
    device_name="NA"
    short_device_name="NA"
    local tmp=`lspci -s $PCI | cut -d\[ -f2 | tr -d ]`
    if [ -n "$tmp" ]; then
        device_name=$tmp
        short_device_name=`echo $device_name | tr [:upper:] [:lower:] | sed -e 's/connectx-/cx/' -e 's/ //g'`
        if [ "$short_device_name" == "cx5ex" ]; then
            short_device_name="cx5"
        fi
    fi
}

function __setup_common() {
    [ -f /etc/os-release ] && . /etc/os-release
    ANSI_COLOR0="$COLOR0${ANSI_COLOR}m"
    if [ -n "$PRETTY_NAME" ]; then
        kmsg $PRETTY_NAME
        echo -e "${ANSI_COLOR0}$PRETTY_NAME$NOCOLOR"
    fi
    log `uname -nsrp`

    require_interfaces NIC NIC2
    require_cmd lspci ethtool tc bc
    fail_if_err

    sysfs_pci_device=`readlink -f /sys/class/net/$NIC/../../`
    SRIOV_NUMVFS_NIC=$sysfs_pci_device/sriov_numvfs
    sysfs_pci_device2=`readlink -f /sys/class/net/$NIC2/../../`
    SRIOV_NUMVFS_NIC2=$sysfs_pci_device2/sriov_numvfs
    PCI=$(basename `readlink /sys/class/net/$NIC/device`)
    PCI2=$(basename `readlink /sys/class/net/$NIC2/device`)
    DEVICE=`cat /sys/class/net/$NIC/device/device`
    FW=`get_nic_fw $NIC`

    __get_device_name

    status="NIC $NIC FW $FW PCI $PCI DEVICE $DEVICE $device_name"
    log $status

    # mlnx ofed from sources will show the static version from upstream
    # and not real mlnx ofed version.
    is_ofed && log "MLNX_OFED `modinfo --field version mlx5_core`"
    __test_for_devlink_compat

    setup_expected_steering_mode
    setup_iptables_legacy
    clear_warn_once
    kmemleak_scan_per_test && kmemleak_clear
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
        if update-alternatives --list | grep -w iptables | grep -q legacy ; then
            return
        fi
        update-alternatives  --set iptables /usr/sbin/iptables-legacy
    fi
}

function set_trusted_vf_mode() {
    local nic=$1
    local pci=$(basename `readlink /sys/class/net/$nic/device`)

    mlxreg -d $pci --reg_id 0xc007 --reg_len 0x40 --indexes "0x0.31:1=1" --yes --set "0x4.0:32=0x1"
}

function get_flow_steering_mode() {
    local nic=$1
    local pci=$(basename `readlink /sys/class/net/$nic/device`)

    if [ "$devlink_compat" = 1 ]; then
        cat `devlink_compat_dir $nic`/steering_mode
    else
        devlink dev param show pci/$pci name flow_steering_mode | grep "runtime value" | awk {'print $NF'}
    fi
}

function set_flow_steering_mode() {
    local nic=$1
    local mode=$2
    local pci=$(basename `readlink /sys/class/net/$nic/device`)

    if [ "$devlink_compat" = 1 ]; then
        echo $mode > `devlink_compat_dir $nic`/steering_mode || fail "Failed to set $mode flow steering mode"
    else
        devlink dev param set pci/$pci name flow_steering_mode value $mode cmode runtime || fail "Failed to set $mode flow steering mode"
    fi

    log "Set $mode flow steering mode on $nic"
}

function setup_expected_steering_mode() {
    if [ -z "$STEERING_MODE" ]; then
        return
    fi
    local mode1=`get_flow_steering_mode $NIC`
    local mode2=`get_flow_steering_mode $NIC2`
    if [ "$mode1" != $STEERING_MODE ]; then
        config_sriov 2
        enable_legacy $NIC
        set_flow_steering_mode $NIC $STEERING_MODE
    fi
    if [ "$mode2" != $STEERING_MODE ]; then
        config_sriov 2 $NIC2
        enable_legacy $NIC2
        set_flow_steering_mode $NIC2 $STEERING_MODE
    fi
    mode1=`get_flow_steering_mode $NIC`
    mode2=`get_flow_steering_mode $NIC2`
    log "Flow steering mode for $NIC is $mode1"
    log "Flow steering mode for $NIC2 is $mode2"
}

function is_bonded() {
    local rc
    for _ in `seq 5`; do
        sleep 1 # wait a second. saw up to 5 sec on nic mode.
        # look for "lag map" and not "modify lag map".
        # "lag map" print is from create lag.
        # "modify lag map" print is from modify lag.
        dmesg | tail -n10 | grep -E "lag map port 1:. port 2:." | grep -v "modify lag map"
        rc=$?
        if [ $rc -eq 0 ]; then
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
    log "Config bonding $nic1 $nic2 mode $mode"
    if is_rh72_kernel ; then
        ip link add name bond0 type bond
        echo 100 > /sys/class/net/bond0/bonding/miimon
        echo $mode > /sys/class/net/bond0/bonding/mode
    else
        ip link add name bond0 type bond mode $mode miimon 100 || fail "Failed to create bond interface"
    fi
    ip link set dev $nic1 down
    ip link set dev $nic2 down
    ip link set dev $nic1 master bond0
    ip link set dev $nic2 master bond0
    ip link set dev bond0 up
    ip link set dev $nic1 up
    ip link set dev $nic2 up
}

function config_bonding() {
    __config_bonding $@
    if ! is_bonded ; then
        err "Driver bond failed"
        return
    fi
    reset_tc bond0
}

function clear_bonding() {
    local nic1=${1:-$NIC}
    local nic2=${2:-$NIC2}
    ip link del bond0 &>/dev/null
    ip link set dev $nic1 nomaster &>/dev/null
    ip link set dev $nic2 nomaster &>/dev/null
}

function remote_disable_sriov() {
    local nic1=$REMOTE_NIC
    local nic2=$REMOTE_NIC2
    echo "Disabling sriov in remote server"
    local cmd="echo 0 > /sys/class/net/$nic1/device/sriov_numvfs"
    if [ -n "$nic2" ]; then
        cmd+="; echo 0 > /sys/class/net/$nic2/device/sriov_numvfs"
    fi
    on_remote "$cmd" &>/dev/null
}

function config_remote_bonding() {
    local nic1=$REMOTE_NIC
    local nic2=$REMOTE_NIC2
    local mode=${3:-active-backup}
    log "Config remote bonding $nic1 $nic2 mode $mode"
    on_remote modprobe -q bonding || fail "Remote missing module bonding"
    clear_remote_bonding
    on_remote ip link add name bond0 type bond || fail "Failed to create remote bond interface"
    on_remote "echo 100 > /sys/class/net/bond0/bonding/miimon; \
               echo $mode > /sys/class/net/bond0/bonding/mode; \
               ip link set dev $nic1 down; \
               ip link set dev $nic2 down; \
               ip link set dev $nic1 master bond0; \
               ip link set dev $nic2 master bond0; \
               ip link set dev bond0 up; \
               ip link set dev $nic1 up; \
               ip link set dev $nic2 up"
}

function clear_remote_bonding() {
    on_remote "ip link set dev $REMOTE_NIC nomaster &>/dev/null; \
               ip link set dev $REMOTE_NIC2 nomaster &>/dev/null; \
               ip link del bond0 &>/dev/null"
}

function require_mlxreg() {
    [[ -e /usr/bin/mlxreg ]] || fail "Missing mlxreg"
}

function require_mlxdump() {
    [[ -e /usr/bin/mlxdump ]] || fail "Missing mlxdump"
}

function require_mlxconfig() {
    [[ -e /usr/bin/mlxconfig ]] || fail "Missing mlxconfig"
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

function cloud_fw_reset() {
    local ip=`hostname -i | tr " "  "\n" | grep -v : | tail -1`
    disable_sriov
    unload_modules
    /workspace/cloud_tools/cloud_firmware_reset.sh -ips $ip || err "cloud_firmware_reset failed"
    load_modules
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
    if is_cloud ; then
        cloud_fw_reset
    else
        mlxfwreset -y -d $PCI reset || err "mlxfwreset failed"
    fi
    wait_for_ifaces
    setup_expected_steering_mode
}

function fw_config() {
    mlxconfig -y -d $PCI set $@ || err "mlxconfig failed to set $@"
}

function fw_query_val() {
    mlxconfig -d $PCI q | grep $1 | awk {'print $2'}
}

function ssh2() {
    ssh -tt -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=3 "$@"
}

function on_remote_dt() {
    # We assume that the scripts are accessible at the same location on remote host ${DIR}
    ssh2 $REMOTE_SERVER "cat > /tmp/dt_cmd.$$.sh <<EOF
export CONFIG=${CONFIG}
export NO_TITLE=1
. ${DIR}/common.sh

$@
EOF
bash /tmp/dt_cmd.$$.sh && /bin/rm -f /tmp/dt_cmd.$$.sh"
}

function on_remote() {
    ssh2 $REMOTE_SERVER "$@"
}

function require_remote_server() {
    if [ -z "$REMOTE_SERVER" ]; then
        fail "Remote server is not configured"
    fi
    if [ -z "$REMOTE_NIC" ]; then
        fail "Remote nic is not configured"
    fi
    log "Remote server $REMOTE_SERVER"
    on_remote true || fail "Remote command failed"
}

function kmsg() {
    local m=$@
    if [ -w /dev/kmsg ]; then
        echo -e ":test: $m" >>/dev/kmsg
    fi
}

function title2() {
    local title=${1:-`basename $0`}
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
        tc qdisc add dev $nic1 ingress $TC_ARG || err "Failed to add ingress qdisc to $nic1"
    done
}

function reset_tc_cacheable() {
    TC_ARG="cacheable"
    reset_tc $@
    unset TC_ARG
}

function log() {
    echo $@
    kmsg $@
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
    echo -e "${RED}ERROR: $m$NOCOLOR" >>/dev/stderr
    kmsg "ERROR: $m"
    exit 1
}

function err() {
    local m=${@:-Failed}
    if [ "$__ignore_errors" == "1" ]; then
        log $m
        return
    fi
    TEST_FAILED=1
    echo -e "${RED}ERROR: $m$NOCOLOR"
    kmsg "ERROR: $m"
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
    echo -e "$LIGHTBLUE* $@$NOCOLOR"
    kmsg $@
}

function config_vf() {
    local ns=$1
    local vf=$2
    local rep=$3
    local ip=$4
    local mac=$5 # optional
    local prefix=24

    if [[ "$ip" == *":"* ]]; then
        # ipv6
        prefix=64
    fi

    echo "[$ns] $vf (${mac:+$mac/}$ip) -> $rep"
    ip address flush dev $rep
    ip link set dev $rep up
    ip netns add $ns
    ${mac:+ip link set $vf address $mac}
    ip link set $vf netns $ns
    ip -netns $ns address replace dev $vf $ip/$prefix
    ip -netns $ns link set $vf up
}

function add_vf_vlan() {
    local ns=$1
    local vf=$2
    local rep=$3
    local ip=$4
    local vlan=$5
    local mac=$6 # optional
    local prefix=24

    if [[ "$ip" == *":"* ]]; then
        # ipv6
        prefix=64
    fi

    echo "[$ns] $vf.$vlan (${mac:+$mac/}$ip) -> $rep"
    ip -netns $ns link add link $vf name $vf.$vlan type vlan id $vlan
    ${mac:+ip link set $vf.$vlan address $mac}
    ip -netns $ns address replace dev $vf.$vlan $ip/$prefix
    ip -netns $ns link set $vf.$vlan up
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

function get_reps() {
    local i
    local nic=${1:-$NIC}
    local out=""
    local sid1=`get_sw_id $nic`
    local sid2

    if [ -z "$sid1" ]; then
        echo "get_rep: Failed to get sw id for $nic"
        return
    fi

    for i in `ls -1 /sys/class/net`; do
        if [ $i == $nic ]; then continue ; fi
        sid2=`get_sw_id $i`
        if [ "$sid1" == "$sid2" ]; then
            out+=" $i"
        fi
    done
    echo $out
    # usage example:
    #        local reps=`get_reps`
    #        cmd="echo -n $reps | xargs -I {} -d ' ' ip link set dev {} up"
}

function __get_reps() {
    local nic=$1
    # XXX: we might miss reps if not using the udev rule
    ls -1 /sys/class/net/ | grep ${nic}_[0-9]
}

function bring_up_reps() {
    local nic=${1:-$NIC}
    local ifs

    # XXX: we might miss reps if not using the udev rule
    ifs=`__get_reps $nic`

    if [ -z "$ifs" ]; then
        warn "bring_up_reps: didn't find reps for $nic"
        return
    fi

    local cmd="echo -n '$ifs' | xargs -I {} ip link set dev {} up"
    local c=`echo $ifs | wc -w`
    local x=`echo $c*0.6 | bc`
    echo "bring up $c reps with timeout $x seconds"

    timeout $x sh -c "$cmd"
    if [ $? -eq 124 ]; then
        err "Timed out bringing interfaces up after $x seconds"
    fi
}

function get_vfs_count() {
    local nic=$1
    ls -1d /sys/class/net/$nic/device/virtfn* 2>/dev/null | wc -l
}

function get_reps_count() {
    local nic=$1
    __get_reps $nic | wc -l
}

function wait_for_reps() {
    local i
    local nic=$1
    local count=$2
    local reps=0

    for i in `seq 4`; do
        reps=`get_reps_count $nic`
        if [ "$reps" = "$count" ]; then
            break
        fi
        sleep 1
    done
}

function devlink_compat_dir() {
    local nic=$1
    local pci=$(basename `readlink /sys/class/net/$nic/device`)
    eval echo "$__devlink_compat_dir"
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
        fail "compat: Failed to set mode $mode"
    fi
}

function switch_mode() {
    local mode=$1
    local nic=${2:-$NIC}
    local pci=$(basename `readlink /sys/class/net/$nic/device`)
    local extra="$extra_mode"
    local vf_count=`get_vfs_count $nic`

    log "Change $nic eswitch ($pci) mode to $mode $extra"

    if [ "$devlink_compat" = 1 ]; then
        local tmp=$(cat `devlink_compat_dir $nic`/mode)
        if [ "$mode" != "$tmp" ]; then
            echo $mode > `devlink_compat_dir $nic`/mode || fail "Failed to set mode $mode"
            wait_switch_mode_compat $nic $mode $vf_count
        fi
    else
        devlink dev eswitch set pci/$pci mode $mode $extra || fail "Failed to set mode $mode"
    fi

    if [ "$mode" = "switchdev" ]; then
        wait_for_reps $nic $vf_count
        bring_up_reps $nic
    fi

    wait_for_ifaces
}

function switch_mode_no_rep() {
    local mode=$1
    local nic=${2:-$NIC}
    local pci=$(basename `readlink /sys/class/net/$nic/device`)

    log "Change $nic eswitch ($pci) mode to $mode"

    devlink dev eswitch set pci/$pci mode $mode $extra || fail "Failed to set mode $mode"
}

function switch_mode_legacy() {
    switch_mode legacy $1
}

function switch_mode_switchdev() {
    switch_mode switchdev $1
}

function switch_mode_no_rep_switchdev() {
    switch_mode_no_rep switchdev $1
}

function get_eswitch_mode() {
    if [ "$devlink_compat" = 1 ]; then
        cat `devlink_compat_dir $NIC`/mode
    else
        devlink dev eswitch show pci/$PCI | grep -o " mode [a-z]\+" | awk {'print $2'}
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
        mode=`get_eswitch_inline_mode`
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

function require_multipath_support() {
    local m=""

    if [ "$devlink_compat" = 1 ]; then
        if [ -e `devlink_compat_dir $NIC`/multipath ]; then
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
    local i
    local net
    for i in $@; do
        net=${!i}
        [ -z $net ] && fail "Var $i is empty"
        [ ! -e /sys/class/net/$net ] && fail "Cannot find interface $net"
    done
}

function enable_multipath() {
    if [ "$devlink_compat" = 1 ]; then
        echo enabled > `devlink_compat_dir $NIC`/multipath
    else
        devlink dev eswitch set pci/$PCI multipath enable
    fi
}

function disable_multipath() {
    if [ "$devlink_compat" = 1 ]; then
        echo disabled > `devlink_compat_dir $NIC`/multipath
    else
        devlink dev eswitch set pci/$PCI multipath disable
    fi
}

function enable_switchdev() {
    local nic=${1:-$NIC}
    unbind_vfs $nic
    switch_mode_switchdev $nic
}

function enable_norep_switchdev() {
    local nic=${1:-$NIC}
    unbind_vfs $nic
    switch_mode_no_rep_switchdev $nic
}

function enable_legacy() {
    local nic=${1:-$NIC}
    unbind_vfs $nic
    switch_mode_legacy $nic
}

function set_vport_match_legacy() {
    if [ "$devlink_compat" = 1 ]; then
        echo "legacy" > /sys/class/net/$NIC/compat/devlink/vport_match_mode || err "Failed to set vport match mode legacy"
    else
        devlink dev param set pci/$PCI name esw_port_metadata value false \
            cmode runtime || err "Failed to set esw_port_metadata to false"
    fi
}

function set_vport_match_metadata() {
    if [ "$devlink_compat" = 1 ]; then
        echo "metadata" > /sys/class/net/$NIC/compat/devlink/vport_match_mode || err "Failed to set vport match mode metadata"
    else
        devlink dev param set pci/$PCI name esw_port_metadata value true \
            cmode runtime || err "Failed to set esw_port_metadata to true"
    fi
}

function set_steering_sw() {
    if [ "$devlink_compat" = 1 ]; then
        echo smfs > /sys/class/net/$NIC/compat/devlink/steering_mode || err "Failed to set steering sw"
    else
        devlink dev param set pci/$PCI name flow_steering_mode value "smfs" \
            cmode runtime || err "Failed to set steering sw"
    fi
}

function set_steering_fw() {
    if [ "$devlink_compat" = 1 ]; then
         echo dmfs > /sys/class/net/$NIC/compat/devlink/steering_mode || err "Failed to set steering fw"
    else
         devlink dev param set pci/$PCI name flow_steering_mode value "dmfs" \
             cmode runtime || err "Failed to set steering fw"
    fi
}

function get_multipath_mode() {
    if [ "$devlink_compat" = 1 ]; then
        cat `devlink_compat_dir $NIC`/multipath
    else
        devlink dev eswitch show pci/$PCI | grep -o "\bmultipath [a-z]\+" | awk {'print $2'}
    fi
}

function config_sriov() {
    local num=${1:-2}
    local nic=${2:-$NIC}
    local numvfs

    if [ "$nic" == "$NIC" ]; then
        numvfs=$SRIOV_NUMVFS_NIC
    elif [ "$nic" == "$NIC2" ]; then
        numvfs=$SRIOV_NUMVFS_NIC2
    fi

    [ -z "$numvfs" ] && fail "numvfs for $nic is NULL"

    local cur=`cat $numvfs`
    if [ $cur -eq $num ]; then
        return
    else
        echo 0 > $numvfs
    fi
    echo $num > $numvfs || fail "Failed to config $num VFs on $nic"
    sleep 0.5
    udevadm trigger -c add -s net &>/dev/null
}

function disable_sriov() {
    config_sriov 0 $NIC
    config_sriov 0 $NIC2
}

function enable_sriov() {
    config_sriov 2 $NIC
    config_sriov 2 $NIC2
}

function disable_sriov_port2() {
    config_sriov 0 $NIC2
}

function enable_sriov_port2() {
    config_sriov 2 $NIC2
}

function set_macs() {
    local count=$1 # optional
    $SET_MACS $NIC $count
}

function unbind_vfs() {
    local i
    local nic=${1:-$NIC}
    log "unbind vfs of $nic"
    for i in `ls -1d /sys/class/net/$nic/device/virt* 2>/dev/null`; do
        vfpci=$(basename `readlink $i`)
        if [ -e /sys/bus/pci/drivers/mlx5_core/$vfpci ]; then
            echo $vfpci > /sys/bus/pci/drivers/mlx5_core/unbind
        fi
    done
}

function get_bound_vfs_count() {
    local nic=$1
    local vfs=(/sys/class/net/*/device/physfn/net/$nic)
    local count=${#vfs[@]}

    echo $count
}

function wait_for_vfs() {
    local i
    local nic=$1
    local count=$2
    local vfs=0

    for i in `seq 10`; do
        vfs=`get_bound_vfs_count $nic`
        if [ "$vfs" = "$count" ]; then
            break
        fi
        sleep 1
    done
}

function bind_vfs() {
    local i
    local nic=${1:-$NIC}
    local vf_count=`get_vfs_count $nic`

    log "bind vfs of $nic"
    for i in `ls -1d /sys/class/net/$nic/device/virt*`; do
        vfpci=$(basename `readlink $i`)
        if [ ! -e /sys/bus/pci/drivers/mlx5_core/$vfpci ]; then
            echo $vfpci > /sys/bus/pci/drivers/mlx5_core/bind
        fi
    done

    wait_for_vfs $nic $vf_count
    udevadm settle # wait for udev renaming after bind
}

function get_sw_id() {
    cat /sys/class/net/$1/phys_switch_id 2>/dev/null
}

function get_port_name() {
    cat /sys/class/net/$1/phys_port_name 2>/dev/null
}

function get_parent_port_name() {
    local a=`cat /sys/class/net/$1/phys_port_name 2>/dev/null`
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
        pn2=`get_parent_port_name $i`
        if [ "$id" = "$id2" ] && [ "$pn" = "$pn2" ]; then
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

function get_ms_time() {
    echo $(($(date +%s%N)/1000000))
}

function start_test_timestamp() {
    # sleep to get a unique timestamp
    sleep 1
    _check_start_ts=`date +"%s"`
}

function get_test_time_elapsed() {
    local now=`date +"%s"`
    local sec=`echo $now - $_check_start_ts + 1 | bc`
    echo $sec
}

function check_kasan() {
    local sec=`get_test_time_elapsed`
    a=`journalctl --since="$sec seconds ago" | grep KASAN || true`
    if [ "$a" != "" ]; then
        err "$a"
        return 1
    fi
    return 0
}

function check_for_ofed_memtrack_errors() {
    local sec=$1
    local look="memtrack_report: Summary: .* leak(s) detected"
    local filter="memtrack_report: Summary: 0 leak(s) detected"
    local a=`journalctl --since="$sec seconds ago" | grep -i "$look" |grep -v -i "$filter" || true`

    if [ "$a" != "" ]; then
        err "Detected memtrack errors in the log"
        echo "$a"
    fi
}

function check_for_errors_log() {
    journalctl --sync &>/dev/null || sleep 0.5
    local rc=0
    local sec=`get_test_time_elapsed`
    local look="DEADLOCK|possible circular locking|possible recursive locking|\
WARNING:|RIP:|BUG:|refcount > 1|refcount_t|segfault|in_atomic|hw csum failure|\
list_del corruption|which is not allocated|Objects remaining|assertion failed|\
Slab cache still has objects|new suspected memory leaks|Unknown object at|\
warning: consoletype is now deprecated|warning: use tty|\
kfree for unknown address|UBSAN"
    local fw_errs="health compromised|firmware internal error|assert_var|\
Command completion arrived after timeout|Error cqe|failed reclaiming pages"
    local look_ahead="Call Trace:|Allocated by task|Freed by task"
    local look_ahead_count=12
    local filter="networkd-dispatcher|nm-dispatcher|uses legacy ethtool link settings|EAL: WARNING: cpu flags constant_tsc=yes nonstop_tsc=no"

    look="$look|$fw_errs"
    local a=`journalctl --since="$sec seconds ago" | grep -E -i "$look" | grep -v -E -i "$filter" || true`
    local b=`journalctl --since="$sec seconds ago" | grep -E -A $look_ahead_count -i "$look_ahead" || true`
    if [ "$a" != "" ] || [ "$b" != "" ]; then
        err "Detected errors in the log"
        rc=1
    fi
    [ "$a" != "" ] && echo "$a"
    [ "$b" != "" ] && echo "$b"

    check_for_ofed_memtrack_errors $sec

    return $rc
}

function check_for_err() {
    local look="$1"
    local sec=`get_test_time_elapsed`
    local a=`journalctl --since="$sec seconds ago" | grep -E -i "$look" || true`

    if [ "$a" != "" ]; then
        err "Detected errors in the log"
        echo "$a"
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
    local now=`date +"%s"`
    local sec=`echo $now - $_check_syndrome_start + 1 | bc`
    local a=`journalctl --since="$sec seconds ago" | grep syndrome || true`
    if [ "$a" != "" ]; then
        a=`echo -e "$a" | uniq`
        err "$a"
        return 1
    fi
    return 0
}

function expect_syndrome() {
    local expected="$1"
    # avoid same time as start_check_syndrome
    sleep 1
    local now=`date +"%s"`
    local sec=`echo $now - $_check_syndrome_start + 1 | bc`
    local a=`journalctl --since="$sec seconds ago" | grep syndrome | grep -v $expected || true`
    if [ "$a" != "" ]; then
        a=`echo -e "$a" | uniq`
        err "$a"
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

function ovs_dump_ovs_flows() {
    local args=$@
    ovs-appctl dpctl/dump-flows $args type=ovs 2>/dev/null
}

function ovs_clear_bridges() {
    ovs-vsctl list-br | xargs -r -L 1 ovs-vsctl del-br 2>/dev/null
}

function service_ovs() {
    local action=$1
    local ovs="openvswitch"
    local a=`systemctl show -p LoadError $ovs | grep -o DBus.Error`
    if [ "$a" = "DBus.Error" ]; then
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
        warn "OVS hw-offload is disabled"
    fi
    a=`ovs-vsctl get Open_vSwitch . other_config:max-idle 2>/dev/null`
    if [ -n "$a" ]; then
        warn "OVS cleaning max-idle"
        ovs-vsctl remove Open_vSwitch . other_config max-idle
    fi
    check_dpdk_init
}

function check_dpdk_init() {
    local force=0
    local want=""
    local want_extra="-a $PCI,representor=[0,1],dv_xmeta_en=1,mtr_log_max_num=0,log_max_flow_per_mtr=0"

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
           ovs-vsctl set Open_vSwitch . other_config:dpdk-init=true
           ovs-vsctl set Open_vSwitch . other_config:dpdk-extra="$want_extra"
        else
           ovs-vsctl remove Open_vSwitch . other_config dpdk-init
           ovs-vsctl remove Open_vSwitch . other_config dpdk-extra
        fi
        stop_openvswitch
        service_ovs start
    fi
}

function restart_openvswitch() {
    stop_openvswitch
    service_ovs start
    check_ovs_settings
    sleep 1
}

function start_clean_openvswitch() {
    restart_openvswitch
    ovs_clear_bridges
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

function unload_modules() {
    log "unload modules"
    if [ -e /etc/init.d/openibd ]; then
        service openibd force-stop || fail "Failed to stop openibd service"
    else
        modprobe -r -q mlx5_vdpa || true
        modprobe -r -q mlx5_ib || true
        modprobe -r mlx5_core || fail "Failed to unload modules"
    fi
}

function load_modules() {
    log "load modules"
    if [ -e /etc/init.d/openibd ]; then
        service openibd force-start || fail "Failed to start openibd service"
    else
        modprobe mlx5_core || fail "Failed to load modules"
    fi
}

function reload_modules() {
    log "reload modules"
    unload_modules
    load_modules
    wait_for_ifaces

    check_kasan || err "Detected KASAN in journalctl"
    set_macs
    setup_expected_steering_mode
    echo "reload modules done"
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
    tc filter show dev $dev ingress prio $prio | grep -q -w in_hw || err "rule not in hw dev $dev"
}

function verify_not_in_hw() {
    local dev=$1
    local prio=$2
    tc filter show dev $dev ingress prio $prio | grep -q -w not_in_hw || err "rule expected not in hw dev $dev"
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
    if [ "$ID" = "ubuntu" ]; then
        echo `ipcalc -n $ip/$net | grep Network: | awk {'print $2'}`
    else
        echo `ipcalc -n $ip/$net | cut -d= -f2`/$net
    fi
}

function eval2() {
    local err
    eval $@
    err=$?
    test $err != 0 && err "Command failed ($err): $@"
    return $err
}

function fail_if_err() {
    local m=${@:-TEST FAILED}
    if [ $TEST_FAILED != 0 ]; then
        kill_all_bgs
        check_for_errors_log
        fail $m
    fi
}

function kill_all_bgs() {
    local bgs=$(jobs -p)
    if [ -n "$bgs" ]; then
        kill -9 $(jobs -p) 2>/dev/null
        kmsg "Wait for bgs"
        wait $bgs &>/dev/null
    fi
}

function reload_driver_per_test() {
    [ "$RELOAD_DRIVER_PER_TEST" == 1 ] && return 0
    return 1
}

function test_done() {
    kill_all_bgs
    set +e
    reload_driver_per_test && reload_modules
    kmemleak_scan_per_test && kmemleak_scan
    check_for_errors_log
    echo "runtime: `get_test_time_elapsed`"
    if [ $TEST_FAILED == 0 ]; then
        success "TEST PASSED"
    else
        fail "TEST FAILED"
    fi
}

function not_relevant_for_nic() {
    local nic
    for nic in $@ ; do
        if [ "$short_device_name" == "$nic" ]; then
            fail "Test not relevant for $device_name"
        fi
    done
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

function not_relevant_for_cx5() {
    not_relevant_for_nic cx5
}

function not_relevant_for_cx4() {
    not_relevant_for_nic cx4
}

function not_relevant_for_cx4lx() {
    not_relevant_for_nic cx4lx
}

function relevant_for_cx4() {
    relevant_for_nic cx4 cx4lx
}

function relevant_for_cx5() {
    relevant_for_nic cx5 cx5ex
}

function require_fw_opt() {
    mlxconfig -d $PCI q | grep -q -w $1
    if [ "$?" != 0 ]; then
        fail "fw option $1 is not supported"
    fi
}

function relevant_for_cx4() {
    if [ "$DEVICE_IS_CX4_LX" != 1 ] && [ "$DEVICE_IS_CX4_LX" != 1 ]; then
        log "SKIP (Test relevant for ConnectX-4)"
        exit 0
    fi
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
        fail "Missing CONFIG"
    fi

    echo "Loading config $conf"
    . $conf

    test -n "$FORCE_VF2" && VF2=$FORCE_VF2
    test -n "$FORCE_REP2" && REP2=$FORCE_REP2
}

function __cleanup() {
    err "Terminate requested"
    exit 1
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
    config_sriov 0 $NIC2
}

function warn_if_redmine_bug_is_open() {
    local i
    local issues=`head -n50 $DIR/$TESTNAME | grep "^#" | grep -o "Bug SW #[0-9]\+" | cut -d"#" -f2`
    local p=0
    for i in $issues ; do
        redmine_info $i
        if redmine_bug_is_open ; then
            warn "Redmine issue open: $i $RM_SUBJ"
            p=1
        fi
    done
    [ $p -eq 1 ] && sleep 2
}

# 'Closed', 'Fixed', 'External', 'Closed (External)', 'Rejected', 'Closed (Rejected)'
RM_STATUS_CLOSED=5
RM_STATUS_REJECTED=6
RM_STATUS_FIXED=16
RM_STATUS_CLOSED_REJECTED=38
RM_STATUS_LIST="$RM_STATUS_CLOSED $RM_STATUS_REJECTED $RM_STATUS_FIXED $RM_STATUS_CLOSED_REJECTED"

function redmine_bug_is_open() {
    local i
    [ "$RM_STATUS" = "" ] && return 1
    for i in $RM_STATUS_LIST ; do
        if [ $RM_STATUS = $i ]; then
            return 1
        fi
    done
    return 0
}

function redmine_info() {
    local id=$1
    local key="1c438dfd8cf008a527ad72f01bd5e1bac24deca5"
    local url="https://redmine.mellanox.com/issues/${id}.json?key=$key"
    RM_STATUS=""
    RM_SUBJ=""
    eval `curl -m 1 -s "$url" | python -c "from __future__ import print_function; import sys, json; i=json.load(sys.stdin)['issue']; print(\"RM_STATUS=%s\nRM_SUBJ=%s\" % (json.dumps(i['status']['id']), json.dumps(i['subject'])))" 2>/dev/null`
    if [ -z "$RM_STATUS" ]; then
        warn "Failed to fetch redmine info"
    fi
}

function verify_mlxconfig_for_sf() {
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

### workarounds
function wa_reset_multipath() {
    # we currently switch to legacy and back because of an issue
    # when multipath is ready.
    # Bug SW #1391181: [ASAP MLNX OFED] Enabling multipath only becomes enabled
    # when changing mode from legacy to switchdev
    enable_legacy $NIC
    enable_legacy $NIC2
    enable_switchdev $NIC
    enable_switchdev $NIC2
}

function smfs_dump() {
    local dump=${1:-dump}
    cat /proc/driver/mlx5_core/smfs_dump/fdb/$PCI > /tmp/$dump
}

function fw_dump() {
    local dump=$1
# if smfs
    smfs_dump $dump
# else if dmfs
#    i=0 && mlxdump -d $PCI fsdump --type FT --gvmi=$i --no_zero > /tmp/port$i || err "mlxdump failed"
}

function indir_table_used() {
    local dump="/tmp/indir_dump"
    local gvmi=${1:-0}

    mlxdump -d $PCI fsdump --type FT --gvmi=$gvmi --no_zero > $dump|| err "mlxdump failed"
    grep -A5 ip_version $dump | grep -A3 dst_ip_31_0 | grep -A3 vxlan_vni | grep metadata_reg_c_0 >/dev/null
}

function config_remote_vxlan() {
    if [ -z "$VXLAN_ID" ] || [ -z "$REMOTE_IP" ]; then
        err "Cannot config remote vxlan"
        return
    fi
    on_remote "ip link del vxlan1 &>/dev/null; \
               ip link add vxlan1 type vxlan id $VXLAN_ID dev $REMOTE_NIC dstport 4789; \
               ip a flush dev $REMOTE_NIC; \
               ip a add $REMOTE_IP/24 dev $REMOTE_NIC; \
               ip a add $REMOTE/24 dev vxlan1; \
               ip l set dev vxlan1 up; \
               ip l set dev $REMOTE_NIC up"
}

function cleanup_remote_vxlan() {
    on_remote "ip a flush dev $REMOTE_NIC; \
               ip l del dev vxlan1 &>/dev/null"
}

### main
if [ "X${NO_TITLE}" == "X" ]; then
    title2 `basename $0`
fi
__load_config
warn_if_redmine_bug_is_open
start_test_timestamp
trap __cleanup INT
__setup_common
__setup_clean
