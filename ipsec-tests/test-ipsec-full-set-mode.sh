#!/bin/bash

# This is a basic test which tries to move
# to full offload mode

my_dir="$(dirname "$0")"
. $my_dir/common-ipsec.sh

if ! is_ofed; then
    fail "This feature is supported only over OFED"
fi

require_ipsec_mode

function cleanup() {
    ipsec_set_mode none
}

function run_test() {
    title "changing to ipsec full offload mode"
    ipsec_set_mode full
}

trap cleanup EXIT
run_test
trap - EXIT
cleanup
test_done
