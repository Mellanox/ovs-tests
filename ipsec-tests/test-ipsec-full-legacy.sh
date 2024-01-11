#!/bin/bash

my_dir="$(dirname "$0")"
. $my_dir/common-ipsec.sh

require_remote_server

function config() {
    enable_legacy
    on_remote_exec enable_legacy
}

function cleanup() {
    setup_expected_steering_mode
    enable_switchdev
    on_remote_exec "setup_expected_steering_mode
                    enable_switchdev"
}

function run_test() {
    run_test_ipsec_offload 1500 ipv4 transport tcp no_trusted_vfs full_offload
    run_test_ipsec_offload 9000 ipv4 transport tcp no_trusted_vfs full_offload
}

trap cleanup EXIT

config

pci=`get_pf_pci`

title "Test ipsec packet offload with dmfs in legacy"
set_flow_steering_mode $pci dmfs
on_remote_exec set_flow_steering_mode $pci dmfs
config_full
run_test
cleanup_test

title "Test ipsec packet offload with smfs in legacy"
set_flow_steering_mode $pci smfs
on_remote_exec set_flow_steering_mode $pci smfs
config_full
run_test
cleanup_test

cleanup

trap - EXIT
test_done
