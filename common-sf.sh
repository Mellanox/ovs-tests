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
    [ -z "$sfnum" ] && err "sf_get_rep: Expected sfnum" && return
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

function sf_cfg_unbind() {
    echo $1 > /sys/bus/auxiliary/drivers/mlx5_core.sf_cfg/unbind || err "$1: Failed to unbind from sf cfg"
}

function sf_cfg_bind() {
    echo $1 > /sys/bus/auxiliary/drivers/mlx5_core.sf_cfg/bind || err "$1: Failed to bind to sf cfg"
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
    $sfcmd dev param set auxiliary/$dev name $param_name value $value cmode runtime || err "Failed to set sf $dev param $param_name=$value"
}

function sf_disable_netdev() {
    sf_set_param $1 disable_netdev true || err "$1: Failed to disable netdev"
}

function sf_disable_roce() {
    $sfcmd port function cap set $1 roce false || err "$1: Failed to disable roce"
}

function sf_activate() {
    $sfcmd port function set $1 state active || err "$1: Failed to set active state"
    sleep 1
}

function sf_inactivate() {
    $sfcmd port function set $1 state inactive || err "$1: Failed to set inactive state"
}

function delete_sf() {
    $sfcmd port del $1 || err "Failed to delete sf $1"
}

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

function create_sfs() {
    local count=$1
    local pfnum=0
    local i

    title "Create $count SFs"

    for i in `seq $count`; do
        create_sf $pfnum $i || return 1

        local rep=$(sf_get_rep $i)
        [ "$sf_disable_roce" == 1 ] && sf_disable_roce $rep

        sf_activate $rep
        local sf_dev=$(sf_get_dev $i)
        if [ -z "$sf_dev" ]; then
            err "Failed to get sf dev for pfnum $pfnum sfnum $i"
            continue
        fi

        [ "$sf_disable_netdev" == 1 ] && sf_disable_netdev $sf_dev
        [ "$sf_with_cfg" == 1 ] && sf_cfg_unbind $sf_dev && sf_bind $sf_dev

        [ "$sf_disable_netdev" != 1 ] && sleep 0.5

        eval SF$i=`sf_get_netdev $i`
        eval SF_REP$i=`sf_get_rep $i`
        eval SF_DEV$i=`sf_get_dev $i`
    done
}

function unbind_sfs() {
    local sf_dev
    for sf_dev in `get_aux_sf_devices`; do
        sf_unbind `basename $sf_dev`
    done
}

function remove_sfs() {
    title "Delete SFs"

    # WA Deleting SFs while they are binded is extremly slow need to unbind first to make it faster
    unbind_sfs

    local rep
    for rep in `sf_get_all_reps`; do
        sf_inactivate $rep
        delete_sf $rep
    done
}

function config_sfs_eq() {
    local max_cmpl_eqs=$1
    local cmpl_eq_depth=$2
    local async_eq_depth=$3

    title "Configure SFs EQ"

    echo "max_cmpl_eqs: $max_cmpl_eqs"
    echo "cmpl_eq_depth: $cmpl_eq_depth"
    echo "async_eq_depth: $async_eq_depth"

    local sf_dev
    local dev
    for sf_dev in `get_aux_sf_devices`; do
        dev=`basename $sf_dev`
        sf_unbind $dev
        sf_cfg_bind $dev

        sf_set_param $dev max_cmpl_eqs $max_cmpl_eqs
        sf_set_param $dev cmpl_eq_depth $cmpl_eq_depth
        sf_set_param $dev async_eq_depth $async_eq_depth

        sf_cfg_unbind $dev
        sf_bind $dev
    done
}

function sf_reload_aux() {
    local sf_dev=$1
    local cpus=$2

    start_cpu_irq_check
    devlink dev reload auxiliary/$sf_dev
    if [ $? -ne 0 ]; then
        err "$sf_dev: Devlink reload auxiliary failed"
        return 1
    fi
    check_cpu_irq $sf_dev $cpus
    return $?
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

    sf_reload_aux $sf_dev $cpus
    return $?
}

function enbale_irq_reguest_debug() {
    echo "func $irq_reguest_debug_func +p" > /sys/kernel/debug/dynamic_debug/control
}

function disable_irq_reguest_debug() {
    echo "func $irq_reguest_debug_func -p" > /sys/kernel/debug/dynamic_debug/control
}

function start_cpu_irq_check() {
    sleep 1
    _start_irq_check=`get_time_short`
}

function parse_cpus_value() {
    # usage example:
    #        parse_cpus_value 0
    #        parse_cpus_value 2-10
    #        parse_cpus_value 3-5,10
    local cpus=$1
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
            err "did not find matching cpu: $cpu"
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
