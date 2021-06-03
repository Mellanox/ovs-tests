#!/bin/bash

function get_sf_rep() {
    # takes sfnum as parameter
    echo $(mlxdevm port show | grep "pfnum 0 sfnum $1" | grep -E -o "netdev [a-z0-9]+" | awk {'print $2'})
}

function get_sf_rdmadev() {
    local sfnum=$1
    local sf_rdmadev
    local sfnum2
    for sf_rdmadev in `ls /sys/bus/auxiliary/devices/ | grep mlx5_core.sf`; do
        sfnum2=`cat /sys/bus/auxiliary/devices/$sf_rdmadev/sfnum`
        if [[ "$sfnum2" == "$sfnum" ]]; then
            break
        fi
    done
    echo $sf_rdmadev
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
    local sf_rdmadev=$1
    local param_name=$2
    local value=$3
    mlxdevm dev param set auxiliary/$sf_rdmadev name $param_name value $value cmode runtime
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
