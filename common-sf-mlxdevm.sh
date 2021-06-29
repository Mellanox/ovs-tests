#!/bin/bash

function sf_get_rep() {
    local sfnum=$1
    local pfnum=${2:-0}
    [ -z "$sfnum" ] && err "sf_get_rep: Expected sfnum" && return
    mlxdevm port show | grep "pfnum $pfnum sfnum $sfnum" | grep -E -o "netdev [a-z0-9]+" | awk {'print $2'}
}

function sf_get_all_reps() {
    mlxdevm port show | grep sfnum | grep -E -o "netdev [a-z0-9]+" | awk {'print $2'}
}

function get_aux_sf_devices() {
    ls -1d /sys/bus/auxiliary/devices/mlx5_core.sf.*
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
    mlxdevm dev param set auxiliary/$dev name $param_name value $value cmode runtime || err "Failed to set sf $dev param $param_name=$value"
}

function sf_disable_netdev() {
    sf_set_param $1 disable_netdev true || err "$1: Failed to disable netdev"
}

function sf_disable_roce() {
    mlxdevm port function cap set $1 roce false || err "$1: Failed to disable roce"
}

function sf_activate() {
    mlxdevm port function set $1 state active || err "$1: Failed to set active state"
}

function sf_inactivate() {
    mlxdevm port function set $1 state inactive || err "$1: Failed to set inactive state"
}

function delete_sf() {
    mlxdevm port del $1 || err "Failed to delete sf $1"
}

function create_sf() {
    local pfnum=$1
    local sfnum=$2
    mlxdevm port add pci/$PCI flavour pcisf pfnum $pfnum sfnum $sfnum >/dev/null || err "Failed to create sf on pfnum $pfnum sfnum $sfnum"
}

function create_sfs() {
    local count=$1
    local i

    title "Create $count SFs"

    for i in `seq $count`; do
        create_sf 0 $i
        sleep 0.5

        local rep=$(sf_get_rep $i)
        [ "$sf_disable_roce" == 1 ] && sf_disable_roce $rep

        sf_activate $rep
        local sf_dev=$(sf_get_dev $i)

        [ "$sf_disable_netdev" == 1 ] && sf_disable_netdev $sf_dev
        [ "$sf_with_cfg" == 1 ] && sf_cfg_unbind $sf_dev && sf_bind $sf_dev

        [ "$sf_disable_netdev" != 1 ] && sleep 0.5
        local netdev=$(sf_get_netdev $sf_dev 2>/dev/null)
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
