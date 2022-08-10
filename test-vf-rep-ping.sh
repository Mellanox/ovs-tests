#!/bin/bash
#
# Bug SW #1040416: slow path xmit on VF reps broken
# Bug SW #896876: IP fragments sent by VFs are dropped
# Bug SW #1590821: traffic lost for packets with 32k size or above
#
# with tcpdump we could see traffic VF->rep works but rep->VF doesn't.
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

IP1="7.7.7.1"
IP2="7.7.7.2"

enable_switchdev
bind_vfs
require_interfaces NIC VF REP

function cleanup() {
    ip netns del ns0 2> /dev/null
    ifconfig $REP 0
}
trap cleanup EXIT

# make sure uplink is down. reproduces an issue if uplink is down no traffic
# between vf and rep.
ip link set $NIC down
ip link set $NIC up
ip link set $NIC down

cleanup
ifconfig $REP $IP1/24 up
ip netns add ns0
ip link set $VF netns ns0
ip netns exec ns0 ifconfig $VF $IP2/24 up

title "Test ping REP($IP1) -> VF($IP2)"
ping -q -c 10 -i 0.2 -w 4 $IP2 && success || err

title "Test ping VF($IP2) -> REP($IP1)"
ip netns exec ns0 ping -q -c 10 -i 0.2 -w 4 $IP1 && success || err


function test_ping_flood() {
    local count=$1
    local size=$2
    local timeout=15
    local err=0

    TMP1=/tmp/ping1
    TMP2=/tmp/ping2
    TMP3=/tmp/ping3

    title "Test ping flood $size"

    if [ -n "$size" ]; then
        size="-s $size"
    fi
    ping $IP2 -f -c $count $size -w $timeout > $TMP1 &
    ping $IP2 -f -c $count $size -w $timeout > $TMP2 &
    ping $IP2 -f -c $count $size -w $timeout > $TMP3 &
    wait

    for i in 1 2 3; do
        recv=`egrep -o "[0-9]+ received" /tmp/ping$i | cut -d" " -f1`
        if [ -z $recv ]; then
            err "ping$i: Cannot read ping output"
            err=1
        elif [[ $recv -ne $count ]]; then
            err "ping$i: Received $recv packets, expected $count"
            err=1
        fi
    done

    rm -fr $TMP1 $TMP2 $TMP3

    if [[ $err == 0 ]]; then
        success
    fi
}

test_ping_flood 10000
test_ping_flood 600 32768

cleanup
test_done
