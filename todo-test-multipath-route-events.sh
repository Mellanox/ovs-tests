#!/bin/bash

#EXIT_ON_FAILURE=1

NOCOLOR="\033[0;0m"
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;94m"

function log() {
    echo -e $@
    echo -e "$@" >>/dev/kmsg
}

function err() {
    log "${RED}ERROR:$NOCOLOR $@"
}

function cleanup() {
    ip r d 3.3.3.0/24 &>/dev/null
    ip l del dev dummy9 &>/dev/null
    ifconfig ens1f0 0
    ifconfig ens1f1 0
}

function tst() {
    log "${BLUE}TEST$NOCOLOR $@"
}

function chk() {
    local tst="$1"
    local emsg="$2"
    sleep 0.5
    a=`dmesg | tail -n6 | grep "$1"`
    if [ "$?" != 0 ]; then
        err "$2"
        if [ -n "$EXIT_ON_FAILURE" ]; then
            exit 1
        fi
    else
        log "${GREEN}OK${NOCOLOR} $a"
    fi
}

function chkn() {
    local tst="$1"
    local emsg="$2"
    sleep 0.5
    a=`dmesg | tail -n10 | grep "$1"`
    if [ "$?" != 0 ]; then
        log "${GREEN}OK${NOCOLOR}"
    else
        echo $a
        err "$2"
    fi
}

log "cleanup"
cleanup
sleep 1
log "set both ports to sriov and switchdev"
#WA to disable prev multipath
echo 0 > /sys/class/net/ens1f0/device/sriov_numvfs
for i in ens1f0 ens1f1 ; do
    echo 2 > /sys/class/net/$i/device/sriov_numvfs
    /labhome/roid/scripts/ovs/unbind-vfs.sh $i
    /labhome/roid/scripts/ovs/devlink-mode.sh $i switchdev
done
log "bring up gateways"
ifconfig ens1f0 1.1.1.1/24 up
ifconfig ens1f1 2.2.2.1/24 up
route1=1.1.1.1
route2=2.2.2.1
sleep 1
log "create dummy device"
echo "-before dummy"; ip r
ip l add dev dummy9 type dummy &>/dev/null
ifconfig dummy9 3.3.3.1/24 up
echo "-after dummy"; ip r
sleep 1
# here we get ENTRY_REPLACE
tst "create multipath route"
ip r r 3.3.3.0/24 nexthop via 1.1.1.1 dev ens1f0 nexthop via 2.2.2.1 dev ens1f1
chk "Activate multipath" "failed to enter multipath"
echo "-after multipath"; ip r

# ENTRY_DEL event
# not going out from multipath unless going to legacy again so need to do that.
tst "del route"
ip r d 3.3.3.0/24
#chk "remove multipath" "failed to del multipath"
# ENTRY_ADD event
tst "add route"
ip r r 3.3.3.0/24 nexthop via 1.1.1.1 dev ens1f0 nexthop via 2.2.2.1 dev ens1f1
#chk "activate multipath" "failed to enter multipath"

function tst_netdev() {
    local p0=$1
    local r1=$2
    local p1=$3
    local r2=$4

    log "TEST with $p0"

    if [ "$p0" == "ens1f0" ]; then
        lag_p0="modify lag map port 1:1 port 2:1"
        lag_p1="modify lag map port 1:2 port 2:2"
    else
        lag_p0="modify lag map port 1:2 port 2:2"
        lag_p1="modify lag map port 1:1 port 2:1"
    fi
    lag_default="modify lag map port 1:1 port 2:2"

    # link down/up
    tst "link down $p0"
    ifconfig $p0 down
    chk "$lag_p1" "expected affinity to $p1"
    tst "link up $p0"
    ifconfig $p0 up
    chk "$lag_default" "expected affinity default"

    # peer path dead
    tst "peer path dead $p1"
    ip r r 3.3.3.0/24 nexthop via $r1 dev $p0
    chk "$lag_p0" "expected affinity to $p0"
    tst "peer path up $p1"
    # TODO test r2 as first path and r1 as second path
    ip r r 3.3.3.0/24 nexthop via $r1 dev $p0 nexthop via $r2 dev $p1
    chk "$lag_default" "expected affinity default"
}

tst_netdev ens1f0 $route1 ens1f1 $route2
tst_netdev ens1f1 $route2 ens1f0 $route1

#tst "multiple routes - delete second route - vf lag not destroyed"
#ip r r 3.3.3.0/24 nexthop via 1.1.1.1 dev ens1f0 nexthop via 2.2.2.1 dev ens1f1
#ip r r 4.4.4.0/24 nexthop via 1.1.1.1 dev ens1f0 nexthop via 2.2.2.1 dev ens1f1
#ip r d 4.4.4.0/24
#chkn "remove multipath" "didn't expect remove multipath"

tst "multiple routes"
ip r d 3.3.3.0/24
ip r r 4.4.4.0/24 nexthop via 1.1.1.1 dev ens1f0 nexthop via 2.2.2.1 dev ens1f1
ip r r 3.3.3.0/24 nexthop via 1.1.1.1 dev ens1f0 nexthop via 2.2.2.1 dev ens1f1
tst_netdev ens1f0 $route1 ens1f1 $route2
tst_netdev ens1f1 $route2 ens1f0 $route1
ip r d 3.3.3.0/24
ip r d 4.4.4.0/24

tst "multipath 1 port from hca"
ip link add dummy1 type dummy
ifconfig dummy1 8.8.8.1/24 up
ip r r 4.4.4.0/24 nexthop via 1.1.1.1 dev ens1f0 nexthop via 8.8.8.1 dev dummy1
chk "Multipath offload require two ports of the same HCA" "Expected warning"
ip link del dummy1

log "test done"
