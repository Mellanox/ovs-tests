#!/bin/bash

declare -a SF_DEVS
declare -a SF_REPS
declare -a SF_NETDEVS

function get_sf_rep() {
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

function get_sf_netdev() {
    echo $(basename `ls /sys/bus/auxiliary/devices/$1/net`)
}

function sf_cfg_unbind() {
    echo $1 > /sys/bus/auxiliary/drivers/mlx5_core.sf_cfg/unbind
}

function sf_cfg_bind() {
    echo $1 > /sys/bus/auxiliary/drivers/mlx5_core.sf_cfg/bind
}

function sf_bind() {
    echo $1 > /sys/bus/auxiliary/drivers/mlx5_core.sf/bind
}

function sf_unbind() {
    echo $1 > /sys/bus/auxiliary/drivers/mlx5_core.sf/unbind
}

function sf_set_param() {
    local dev=$1
    local param_name=$2
    local value=$3
    mlxdevm dev param set auxiliary/$dev name $param_name value $value cmode runtime
}

function sf_disable_netdev() {
    sf_set_param $1 disable_netdev true
}

function sf_disable_roce() {
    mlxdevm port function cap set $1 roce false
}

function sf_activate() {
    mlxdevm port function set $1 state active
}

function sf_inactivate() {
    mlxdevm port function set $1 state inactive
}

function delete_sf() {
    mlxdevm port del $1
}

function create_sf() {
    local pfnum=$1
    local sfnum=$2
    mlxdevm port add pci/$PCI flavour pcisf pfnum $pfnum sfnum $sfnum &>/dev/null
}

function create_sfs() {
    local count=$1

    title "Create $count SFs with RoCE Disabled"
    local i
    for i in `seq $count`; do
        create_sf 0 $i
        sleep 0.5

        local rep=$(get_sf_rep $i)
        [ "$sf_disable_roce" == 1 ] && sf_disable_roce $rep
        sf_activate $rep

        local sf_dev=$(sf_get_dev $i)

        [ "$sf_disable_netdev" == 1 ] && sf_disable_netdev $sf_dev
        sf_cfg_unbind $sf_dev
        sf_bind $sf_dev

        local netdev=$(get_sf_netdev $sf_dev 2>/dev/null)
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
