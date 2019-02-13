#!/bin/bash
#
# Test ecmp fib events
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-ecmp.sh

require_interfaces NIC NIC2

function cleanup() {
    ip r d $net &>/dev/null
    ip l del dev dummy9 &>/dev/null
    ip l del dev dummy1 &>/dev/null
    ifconfig $NIC 0
    ifconfig $NIC2 0
}

function chk() {
    local tst="$1"
    local emsg="$2"
    sleep 0.5
    a=`dmesg | tail -n6 | grep -m1 "$tst"`
    if [ $? -ne 0 ]; then
        err $emsg
        return 1
    else
        success2 $a
        return 0
    fi
}


log "cleanup"
cleanup
trap cleanup EXIT

route1=1.1.1.1
route2=2.2.2.1
remote=3.3.3.1
net=3.3.3.0/24
net2=4.4.4.0/24

log "create dummy device"
e=0
ip l add dev dummy9 type dummy || e=1
if [ $e -ne 0 ]; then
    fail "Failed to create dummy device - cannot continue."
fi
ifconfig dummy9 $remote/24 up
echo ; ip r ; echo

log "set both ports to sriov and switchdev"
config_ports

log "bring up gateways"
ifconfig $NIC $route1/24 up
ifconfig $NIC2 $route2/24 up
sleep 1

# here we get ENTRY_REPLACE
title "create multipath route"
ip r r $net nexthop via $route1 dev $NIC nexthop via $route2 dev $NIC2
vf_lag_is_active || fail
echo ; ip r ; echo

start_check_syndrome
# ENTRY_DEL event
# not going out from multipath unless going to legacy again so need to do that.
title "del route"
ip r d $net
# no log

# ENTRY_ADD event
title "add route"
ip r r $net nexthop via $route1 dev $NIC nexthop via $route2 dev $NIC2
# no log
check_syndrome

function tst_netdev() {
    local p0=$1
    local r1=$2
    local p1=$3
    local r2=$4

    echo
    log "TEST with $p0"

    if [ "$p0" == "$NIC" ]; then
        lag_p0="modify lag map port 1:1 port 2:1"
        lag_p1="modify lag map port 1:2 port 2:2"
    else
        lag_p0="modify lag map port 1:2 port 2:2"
        lag_p1="modify lag map port 1:1 port 2:1"
    fi
    lag_default="modify lag map port 1:1 port 2:2"

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
}

tst_netdev $NIC $route1 $NIC2 $route2
tst_netdev $NIC2 $route2 $NIC $route1
echo

title "multiple routes"
start_check_syndrome
ip r d $net
ip r r $net2 nexthop via $route1 dev $NIC nexthop via $route2 dev $NIC2
ip r r $net nexthop via $route1 dev $NIC nexthop via $route2 dev $NIC2
tst_netdev $NIC $route1 $NIC2 $route2
tst_netdev $NIC2 $route2 $NIC $route1
ip r d $net
ip r d $net2
check_syndrome
echo

title "multipath 1 hca port and 1 dummy port"
ip link add dummy1 type dummy
ifconfig dummy1 8.8.8.1/24 up
ip r r $net nexthop via $route1 dev $NIC nexthop via 8.8.8.1 dev dummy1
chk "Multipath offload require two ports of the same HCA" "Expected warning"
ip link del dummy1

title "deactivate multipath"
deconfig_ports

test_done
