#!/bin/bash

sfcmd='devlink'
irq_reguest_debug_func='mlx5_irq_request'

function __set_sf_cmd() {
    if which mlxdevm &>/dev/null ; then
        sfcmd='mlxdevm'
    fi
}

function __irq_reguest_debug_func() {
    cat /sys/kernel/debug/dynamic_debug/control | grep mlx5_irqs_request_mask &>/dev/null
    if [[ $? -eq 0 ]]; then
        irq_reguest_debug_func='mlx5_irqs_request_mask'
    fi
}

__set_sf_cmd
__irq_reguest_debug_func

function sf_get_rep() {
    local sfnum=$1
    local pfnum=${2:-0}
    [ -z "$sfnum" ] && return
    $sfcmd port show | grep "pfnum $pfnum sfnum $sfnum" | grep -E -o "netdev [a-z0-9]+" | awk {'print $2'}
}

function sf_get_all_reps() {
    $sfcmd port show | grep sfnum | grep -E -o "netdev [a-z0-9]+" | awk {'print $2'}
}

function get_aux_sf_devices() {
    ls -1d /sys/bus/auxiliary/devices/mlx5_core.sf.* 2>/dev/null
}

function sf_get_dev() {
    local sfnum=$1
    local sf_dev
    local sfnum2
    for sf_dev in `get_aux_sf_devices`; do
        sfnum2=`cat $sf_dev/sfnum`
        if [[ "$sfnum2" == "$sfnum" ]]; then
            basename $sf_dev
            return
        fi
    done
    return 1
}

function sf_get_netdev() {
    local sfnum=$1
    local dev=`sf_get_dev $sfnum`
    basename `ls -1 /sys/bus/auxiliary/devices/$dev/net`
}

function sf_bind() {
    echo $1 > /sys/bus/auxiliary/drivers/mlx5_core.sf/bind || err "$1: Failed to bind to sf core"
}

function sf_unbind() {
    echo $1 > /sys/bus/auxiliary/drivers/mlx5_core.sf/unbind || err "$1: Failed to unbind from sf core"
}

function sf_set_param() {
    local dev=$1
    local param_name=$2
    local value=$3
    local cmode=$4
    devlink dev param set auxiliary/$dev name $param_name value $value cmode $cmode || err "Failed to set sf $dev param $param_name=$value"
}

function sf_disable_roce() {
    $sfcmd port function cap set $1 roce false || err "$1: Failed to disable roce"
}

function sf_activate() {
    $sfcmd port function set $1 state active || err "$1: Failed to activate state"
    sleep 1
}

function sf_inactivate() {
    $sfcmd port function set $1 state inactive || err "$1: Failed to inactivate state"
}

function delete_sf() {
    $sfcmd port del $1 || err "Failed to delete sf $1"
}

# For SF direction
# 1-65535 (0xffff) no direction
# 65536-131071 (0x1ffff) - Network SF
# 131072 (0x20000) and up - Host SF
SF_DIRECTION_NETWORK=65536
SF_DIRECTION_HOST=131072

function create_sf() {
    local pfnum=$1
    local sfnum=$2
    $sfcmd port add pci/$PCI flavour pcisf pfnum $pfnum sfnum $sfnum >/dev/null
    if [ $? -ne 0 ] ; then
        err "Failed to create sf on pfnum $pfnum sfnum $sfnum"
        return 1
    fi
    sleep 1
}

function create_host_direction_sfs() {
    local count=$1
    local start=$SF_DIRECTION_HOST
    local end=$((start+count-1))

    title "Create host direction SFs"
    __create_sfs $start $end
}

function create_network_direction_sfs() {
    local count=$1
    local start=$SF_DIRECTION_NETWORK
    local end=$((start+count-1))

    title "Create network direction SFs"
    __create_sfs $start $end
}

function create_sfs() {
    local count=$1
    local start=1
    local end=$count

    __create_sfs $start $end
}

function __create_sfs() {
    local start=$1
    local end=$2
    local count=$((end-start+1))
    local pfnum=0
    local i netdev

    title "Create $count SFs start sfnum $start"

    for i in `seq $start $end`; do
        create_sf $pfnum $i || break

        local rep=$(sf_get_rep $i)
        if [ -z "$rep" ]; then
            err "Failed to get sf rep for pfnum $pfnum sfnum $i"
            break
        fi
        [ "$sf_disable_roce" == 1 ] && sf_disable_roce $rep

        sf_activate $rep
        local sf_dev=$(sf_get_dev $i)
        if [ -z "$sf_dev" ]; then
            err "Failed to get sf dev for pfnum $pfnum sfnum $i"
            break
        fi

        sf_reload_auxiliary_devices $sf_dev

        sleep 0.5
        netdev=`sf_get_netdev $i`
        [ -z "$netdev" ] && err "Failed to get sf netdev pfnum $pfnum sfnum $i" && break

        eval SF$i=$netdev
        eval SF_REP$i=$rep
        eval SF_DEV$i=$sf_dev
    done

    if [ $TEST_FAILED != 0 ]; then
        remove_sfs
    fi

    fail_if_err "Failed to create sfs"
}

function sf_reload_auxiliary_devices() {
    local sf_dev=$1
    sf_set_param $sf_dev enable_eth true driverinit
# currently breaking mlnx ofed. need to check its supported before enabling or skip err
#    sf_set_param $sf_dev enable_vnet true driverinit
#    sf_set_param $sf_dev enable_rdma true driverinit
    sf_reload_aux $sf_dev
}

function bind_sfs() {
    local sf_dev
    for sf_dev in `get_aux_sf_devices`; do
        sf_bind `basename $sf_dev`
    done
}

function unbind_sfs() {
    local sf_dev
    for sf_dev in `get_aux_sf_devices`; do
        sf_unbind `basename $sf_dev`
    done
}

function remove_sfs() {
    local sfs=`sf_get_all_reps`
    [ -z "$sfs" ] && return

    title "Delete SFs"

    # WA Deleting SFs while they are binded is extremly slow need to unbind first to make it faster
    unbind_sfs

    local rep
    for rep in `sf_get_all_reps`; do
        sf_inactivate $rep
        delete_sf $rep
    done
}

function sf_reload_aux() {
    local sf_dev=$1

    devlink dev reload auxiliary/$sf_dev
    if [ $? -ne 0 ]; then
        err "$sf_dev: Failed to reload auxiliary device"
        return 1
    fi
    return 0
}

function sf_reload_aux_check_cpu_irq() {
    local sf_dev=$1
    local cpus=$2

    start_cpu_irq_check
    sf_reload_aux $sf_dev || return 1
    check_cpu_irq $sf_dev $cpus
}

function sf_set_cpu_affinity() {
    local sf_dev=$1
    local cpus=$2

    log "Setting cpu affinity with value $cpus to $sf_dev"
    $sfcmd dev param set auxiliary/$sf_dev name cpu_affinity value $cpus cmode driverinit
    if [ $? -ne 0 ]; then
        err "$sf_dev: Failed to set cpu affinity"
        return 1
    fi

    sf_reload_aux_check_cpu_irq $sf_dev $cpus
}

function enbale_irq_reguest_debug() {
    echo "func $irq_reguest_debug_func +p" > /sys/kernel/debug/dynamic_debug/control
}

function disable_irq_reguest_debug() {
    echo "func $irq_reguest_debug_func -p" > /sys/kernel/debug/dynamic_debug/control
}

function start_cpu_irq_check() {
    sleep 1
    _start_irq_check=`get_date_time`
}

function parse_cpus_value() {
    # usage example:
    #        parse_cpus_value 0
    #        parse_cpus_value 2-10
    #        parse_cpus_value 3-5,10
    local cpus=${1:?"missing cpus"}
    local extra_cpu

    if [[ $cpus == ?(-)+([0-9]) ]]; then
        cpus="$cpus $cpus"
    else
        cpus=`echo $cpus | sed -E 's/\-/ /g'`

        if [[ $cpus =~ "," ]]; then
            extra_cpu=`echo "${cpus#*,}"`
            cpus=`echo "${cpus%,*}"`
        fi
    fi

    cpus=`seq $cpus`
    cpus+=" $extra_cpu"
    echo $cpus
}

function check_cpu_irq() {
    local sf_dev=$1
    local cpus=$2

    if [ "$_start_irq_check" == "" ]; then
        err "Failed checking cpu irq. invalid start."
        return 1
    fi

    local mlx5_irq_requests=`journalctl --since="$_start_irq_check" | grep $sf_dev | grep $irq_reguest_debug_func || true`

    if [ "$mlx5_irq_requests" == "" ]; then
        err "Can't find mlx5_irq_requests for $sf_dev"
        return 1
    fi

    cpus=`parse_cpus_value $cpus`

    local cpu
    for cpu in $cpus; do
        grep --color "cpu $cpu" <<< $mlx5_irq_requests
        if [ $? -ne 0 ]; then
            err "Can't find matching cpu: $cpu"
            return 1
        fi
    done

    return 0
}

function sf_show_port() {
    $sfcmd port show $1 || err "Failed to show sf $1"
}

function sf_port_rate() {
    $sfcmd port func rate $@
}

function get_all_sf_pci() {
    devlink port show | grep sfnum | awk {'print $1'}
}

function reload_sfs_into_ns() {
    title "Reload SF into ns0"

    ip netns add ns0
    for sf_dev in `get_aux_sf_devices`; do
        local i=`basename $sf_dev`
        devlink dev reload auxiliary/$i netns ns0 || fail "Failed to reload SF"
    done
}

function set_sf_switchdev() {
    title "Set SF switchdev"

    for sf_dev in `get_aux_sf_devices`; do
        local i=`basename $sf_dev`
        ip netns exec ns0 devlink dev eswitch set auxiliary/$i mode switchdev || fail "Failed to config SF switchdev"
    done
}

function verify_single_ib_device() {
    local expected=$1

    title "Verify single IB device with multiple ports"

    local sf_dev=`$SFCMD dev | grep -w sf | head -1`
    local sf_ib_dev=`basename /sys/bus/auxiliary/devices/$sf_dev/infiniband/*`
    rdma link show | grep -w $sf_ib_dev

    local count=`rdma link show | grep -w $sf_ib_dev | wc -l`

    if [ "$count" -ne $expected ]; then
        err "Expected $expected ports"
    else
        success
    fi
}


function __common_sf_exec() {
    local __argv0=$0
    if [ "$__argv0" == "-bash" ] ; then
        __argv0='.'
    fi
    local COMMON_SF=`basename $__argv0`
    if [ "$COMMON_SF" == "common-sf.sh" ]; then
        # script executed directly. evaluate user input.
        local DIR=$(cd "$(dirname ${BASH_SOURCE[0]})" &>/dev/null && pwd)
        . $DIR/common.sh $@
    fi
}

__common_sf_exec $@
