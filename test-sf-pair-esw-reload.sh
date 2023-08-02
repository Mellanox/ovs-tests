#!/bin/bash
#
# Test reload drivers while SFs in switchdev and shared fdb.

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-sf.sh

IP1="7.7.7.1"
IP2="7.7.7.2"

function cleanup() {
    log "cleanup"
    reset_sfs_ns
    remove_sfs
}

trap cleanup EXIT

function config() {
    local count=$1
    local direction=${2:-""}

    title "Config"

    if [ -z $direction ]; then
        create_sfs $count
    elif [ "$direction" == "network" ]; then
        create_network_direction_sfs $count
    elif [ "$direction" == "host" ]; then
        create_host_direction_sfs $count
    elif [ "$direction" == "both" ]; then
        create_network_direction_sfs $count
        create_host_direction_sfs $count
        ((count+=count))
    fi

    set_sf_eswitch
    #reload_sfs_into_ns
    set_sf_switchdev
    verify_single_ib_device $((count*2))
}

enable_switchdev

# 4 sfs reproduced better than 2.
config 4
reload_modules

trap - EXIT
cleanup
test_done
