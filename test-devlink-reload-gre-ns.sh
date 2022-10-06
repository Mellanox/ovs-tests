#!/bin/bash
#
# If namespace ever created in the system and gre modules are loaded then devlink dev reload is stuck.
#
# Bug SW #3156109: Devlink reload get stuck when reloading vf after probing gre modules

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-devlink.sh

function config() {
    title "Config"
    config_sriov 0
    enable_legacy
}

function add_del_ns() {
    # doesn't reproduce with single namespace.
    ip netns add ns0
    ip netns add ns1
    ip netns add ns2
    ip netns add ns3

    ip -all netns delete
}

function load_gre_modules() {
    modprobe -a ip6_gre ip_gre gre
}

function unload_gre_modules() {
    local holders=`ls -1r /sys/module/gre/holders`
    modprobe -r $holders gre
}

function run() {
    title "Pre steps to reproduce the issue"
    load_gre_modules
    # order is important. add/del ns after gre modules are loaded.
    add_del_ns

    title "Devlink reload $NIC"
    devlink_dev_reload $NIC || err "devlink reload failed"

    unload_gre_modules
}

config
run
test_done
