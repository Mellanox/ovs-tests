#!/bin/bash

# This is a basic test which tries to move
# to full offload mode

my_dir="$(dirname "$0")"
. $my_dir/common-ipsec.sh

if ! is_ofed; then
    fail "This feature is supported only over OFED"
fi

require_ipsec_mode

function clean_up() {
    ipsec_set_mode none
}

function run_test() {
    enable_legacy
    title "changing to ipsec full offload mode"
    ipsec_set_mode full
}

trap clean_up EXIT
run_test
trap - EXIT
clean_up
test_done
