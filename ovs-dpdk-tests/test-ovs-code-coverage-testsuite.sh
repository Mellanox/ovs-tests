#!/bin/bash
#
# Test OVS testsuite, works only with OVS bullseye code coverage.
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

trap cleanup_test EXIT

function run() {
    [ -z "$COVFILE" ] && debug "COVFILE is not defined, nth to do !" && return

    local ovs_repo_path=`dirname $COVFILE`
    cd $ovs_repo_path
    make check TESTSUITEFLAGS='-j`nproc`' || err "Testsuite failed"
}

run
trap - EXIT
cleanup_test
test_done
