#!/bin/bash
#
# Test ecmp fib events
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-ecmp.sh

function cleanup() {
    ip r d $net &>/dev/null
    ip r d $net2 &>/dev/null
    ifconfig $NIC 0
    ifconfig $NIC2 0
    log "deconfig ports"
    deconfig_ports
}

function chk() {
    local tst="$1"
    local emsg="$2"
    journalctl --sync &>/dev/null || sleep 0.5
    a=`journalctl --since="1 second ago" | grep -m1 -e "$tst"`
    if [ $? -ne 0 ]; then
        err $emsg
        return 1
    else
        success2 $a
        return 0
    fi
}



route1=1.1.1.1
route2=2.2.2.1
remote=3.3.3.1
net=3.3.3.0/24
net2=4.4.4.0/24

log "cleanup"
cleanup
trap cleanup EXIT

log "config ports"
config_ports

log "bring up gateways"
ifconfig $NIC $route1/24 up
ifconfig $NIC2 $route2/24 up
sleep 1

# here we get ENTRY_REPLACE
title "Create multipath route"
title "Test route replace"
ip r r $net nexthop via $route1 dev $NIC nexthop via $route2 dev $NIC2
is_vf_lag_active || fail
echo ; ip r ; echo

# disabled because of kernel bug
# append not working in ipv4 and actually adds 2 route entries
function case_route_append() {
    title "Test route append"
    ## ENTRY_DEL event
    ## not going out from multipath unless going to legacy again so need to do that.
    ip r d $net
    ## no log
    ## ENTRY_ADD event
    ip r add $net nexthop via $route1 dev $NIC
    ip r append $net nexthop via $route2 dev $NIC2
    ## no log
}

function case_route_add() {
    title "Test route add"
    # ENTRY_DEL event
    # not going out from multipath unless going to legacy again so need to do that.
    ip r d $net
    # no log
    # ENTRY_ADD event
    ip r add $net nexthop via $route1 dev $NIC nexthop via $route2 dev $NIC2
    # no log
    ip r d $net
}

function tst_netdev() {
    local p0=$1
    local r1=$2
    local p1=$3
    local r2=$4

    echo
    title "Tesing case with $p0"

    if [ "$p0" == "$NIC" ]; then
        local lag_p0="lag map:* port 1:1 port 2:1"
        local lag_p1="lag map:* port 1:2 port 2:2"
    else
        local lag_p0="lag map:* port 1:2 port 2:2"
        local lag_p1="lag map:* port 1:1 port 2:1"
    fi
    local lag_default="lag map:* port 1:1 port 2:2"

    title "link down $p0"
    ifconfig $p0 down
    chk "$lag_p1" "expected affinity to $p1"

    title "link up $p0"
    ifconfig $p0 up
    chk "$lag_default" "expected affinity default"

    title "peer path dead $p1"
    ip r r $net nexthop via $r1 dev $p0
    chk "$lag_p0" "expected affinity to $p0"

    title "peer path up $p1"
    # TODO test r2 as first path and r1 as second path
    ip r r $net nexthop via $r1 dev $p0 nexthop via $r2 dev $p1
    chk "$lag_default" "expected affinity default"

    title "new route single nexthop to $p0"
    ip r d $net
    ip r r $net nexthop via $r1 dev $p0
    chk "$lag_p0" "expected affinity to $p0"

    title "restore"
    ip r r $net nexthop via $r1 dev $p0 nexthop via $r2 dev $p1
    chk "$lag_default" "expected affinity default"

    title "link down $p0 + del route"
    ifconfig $p0 down
    ip r r $net nexthop via $r2 dev $p1
    chk "$lag_p1" "expected affinity to $p1"

    title "restore"
    ifconfig $p0 up
    ip r r $net nexthop via $r1 dev $p0 nexthop via $r2 dev $p1
    chk "$lag_default" "expected affinity default"
}

function case_single_route() {
    title "Test single route"
    ip r r $net nexthop via $route1 dev $NIC nexthop via $route2 dev $NIC2
    tst_netdev $NIC $route1 $NIC2 $route2
    tst_netdev $NIC2 $route2 $NIC $route1
    ip r d $net
    echo
}

function case_two_routes() {
    title "Test two routes"
    ip r r $net2 nexthop via $route1 dev $NIC nexthop via $route2 dev $NIC2
    ip r r $net nexthop via $route1 dev $NIC nexthop via $route2 dev $NIC2
    tst_netdev $NIC $route1 $NIC2 $route2
    tst_netdev $NIC2 $route2 $NIC $route1
    ip r d $net
    ip r d $net2
    echo
}

function case_route_metric() {
    title "Test route metric"
    ip r r $net metric 20 nexthop via $route1 dev $NIC nexthop via $route2 dev $NIC2
    ip r r $net2 metric 1 nexthop via $route1 dev $NIC

    title "net2 is expected to take over because of lower metric"
    local lag_p0="lag map:* port 1:1 port 2:1"
    chk "$lag_p0" "expected affinity to $NIC"

    title "restore"
    ip r r $net2 metric 1 nexthop via $route1 dev $NIC nexthop via $route2 dev $NIC2
    local lag_default="lag map:* port 1:1 port 2:2"
    chk "$lag_default" "expected affinity default"

    ip r d $net
    ip r d $net2
    echo
}


case_route_add
case_single_route
case_two_routes
case_route_metric

trap - EXIT
cleanup

test_done
