#!/bin/bash

declare -a SF_DEVS
declare -a SF_REPS
declare -a SF_NETDEVS

function sf_get_rep() {
    # takes sfnum as parameter
    echo $(mlxdevm port show | grep "pfnum 0 sfnum $1" | grep -E -o "netdev [a-z0-9]+" | awk {'print $2'})
}

function sf_get_dev() {
    local sfnum=$1
    local sf_dev
    local sfnum2
    for sf_dev in `ls /sys/bus/auxiliary/devices/ | grep mlx5_core.sf`; do
        sfnum2=`cat /sys/bus/auxiliary/devices/$sf_dev/sfnum`
        if [[ "$sfnum2" == "$sfnum" ]]; then
            break
        fi
    done
    echo $sf_dev
}

function sf_get_netdev() {
    echo $(basename `ls /sys/bus/auxiliary/devices/$1/net`)
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

        SF_DEVS+=($sf_dev)
        SF_REPS+=($rep)
        SF_NETDEVS+=($netdev)
    done
}

function unbind_sfs() {
    local dev
    for dev in "${SF_DEVS[@]}"; do
        sf_unbind $dev
    done
}

function remove_sfs() {
    title "Delete SFs"

    # WA Deleting SFs while they are binded is extremly slow need to unbind first to make it faster
    unbind_sfs

    local rep
    for rep in "${SF_REPS[@]}"; do
        sf_inactivate $rep
        delete_sf $rep
    done

    SF_DEVS=()
    SF_REPS=()
    SF_NETDEVS=()
}

function config_sfs_eq() {
    local max_cmpl_eqs=$1
    local cmpl_eq_depth=$2
    local async_eq_depth=$3

    title "Configure SFs EQ"

    echo "max_cmpl_eqs: $max_cmpl_eqs"
    echo "cmpl_eq_depth: $cmpl_eq_depth"
    echo "async_eq_depth: $async_eq_depth"

    local dev
    for dev in "${SF_DEVS[@]}"; do
        sf_unbind $dev
        sf_cfg_bind $dev

        sf_set_param $dev max_cmpl_eqs $max_cmpl_eqs
        sf_set_param $dev cmpl_eq_depth $cmpl_eq_depth
        sf_set_param $dev async_eq_depth $async_eq_depth

        sf_cfg_unbind $dev
        sf_bind $dev
    done
}
