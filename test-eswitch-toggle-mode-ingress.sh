#!/bin/bash
#
# Test toggle e-switch mode and del ingress
#
# Bug SW #2226884 - call trace after change to legacy over vxlan ipv4 active backup

my_dir="$(dirname "$0")"
. $my_dir/common.sh


function config() {
    enable_switchdev
    require_interfaces NIC
    reset_tc $NIC
    tc qdisc show dev $NIC ingress
    fail_if_err
}

function do_test() {
    enable_legacy &

    # random between 0 and 1.
    local s=`bc <<< "scale=4 ; ${RANDOM}/32767"`
    echo "sleep $s"
    sleep $s
    log "del ingress"
    tc qdisc del dev $NIC ingress
    wait

    # second part of the bug we cannot add ingress qdisc again.
    # first remove in case it exists.
    tc qdisc del dev $NIC ingress &>/dev/null 
    # now try to add
    tc qdisc add dev $NIC ingress || err "Failed to add ingress qdisc to $NIC"
}

config
do_test
test_done
