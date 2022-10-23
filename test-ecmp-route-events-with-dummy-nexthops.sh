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
    ip l del dev dummy4 &>/dev/null
    ip l del dev dummy5 &>/dev/null
    ifconfig $NIC 0
    ifconfig $NIC2 0
    log "deconfig ports"
    deconfig_ports
}

function chk() {
    local tst="$1"
    local emsg="$2"
    sleep 0.5
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
route4=4.4.4.1
route5=5.5.5.1
remote=3.3.3.1
net=3.3.3.0/24
net2=3.3.2.0/24

log "cleanup"
cleanup
trap cleanup EXIT

log "config ports"
config_ports

log "bring up gateways"
ifconfig $NIC $route1/24 up
ifconfig $NIC2 $route2/24 up
ip l add dev dummy4 type dummy || fail "Failed to create dummy device - cannot continue."
ip l add dev dummy5 type dummy || fail "Failed to create dummy device - cannot continue."
ifconfig dummy4 $route4/24
ifconfig dummy5 $route5/24
sleep 1

lag_p0="lag map:* port 1:1 port 2:1"
lag_p1="lag map:* port 1:2 port 2:2"
lag_default="lag map:* port 1:1 port 2:2"

function case_route_add_2_valid_nexthops_out_of_4() {
    title "Test route add"
    ip r r $net \
            nexthop via $route4 dev dummy4 \
            nexthop via $route5 dev dummy5 \
            nexthop via $route1 dev $NIC \
            nexthop via $route2 dev $NIC2

    chk "$lag_default" "expected affinity default"
    ip r d $net
}

function case_route_add_1_valid_nexthops_out_of_3() {
    title "Test route add"
    ip r r $net \
            nexthop via $route4 dev dummy4 \
            nexthop via $route5 dev dummy5 \
            nexthop via $route1 dev $NIC

    chk "$lag_p0" "expected affinity to $NIC"

    ip r r $net \
            nexthop via $route4 dev dummy4 \
            nexthop via $route5 dev dummy5 \
            nexthop via $route2 dev $NIC2

    chk "$lag_p1" "expected affinity to $NIC2"
    ip r d $net
}

function case_route_replace_with_invalid_nexthops() {
    title "Test route add"
    ip r r $net \
            nexthop via $route4 dev dummy4 \
            nexthop via $route5 dev dummy5 \
            nexthop via $route1 dev $NIC \
            nexthop via $route2 dev $NIC2

    chk "$lag_default" "expected affinity default"

    ip r r $net \
            nexthop via $route4 dev dummy4 \
            nexthop via $route5 dev dummy5
    # no prints, mfi should get deleted

    ip r r $net2 \
            nexthop via $route4 dev dummy4 \
            nexthop via $route5 dev dummy5 \
            nexthop via $route2 dev $NIC2
    chk "$lag_p1" "expected affinity to $NIC2"
    ip r d $net2
}

case_route_add_2_valid_nexthops_out_of_4
case_route_add_1_valid_nexthops_out_of_3
case_route_replace_with_invalid_nexthops

trap - EXIT
cleanup

test_done
