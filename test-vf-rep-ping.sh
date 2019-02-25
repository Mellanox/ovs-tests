#!/bin/bash
#
# Bug SW #1040416: slow path xmit on VF reps broken
# Bug SW #896876: IP fragments sent by VFs are dropped
# Bug SW #1590821: [JD] traffic lost for packets with 32k size or above
#
# with tcpdump we could see traffic VF->rep works but rep->VF doesn't.
#

NIC=${1:-ens5f0}
VF=${2:-ens5f2}
REP=${3:-ens5f0_0}
my_dir="$(dirname "$0")"
. $my_dir/common.sh

IP1="7.7.7.1"
IP2="7.7.7.2"

enable_switchdev_if_no_rep $REP
bind_vfs

function cleanup() {
    ip netns del ns0 2> /dev/null
    ifconfig $REP 0
}

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
    TMP1=/tmp/ping1
    TMP2=/tmp/ping2
    TMP3=/tmp/ping3
    COUNT=10000
    TIMEOUT=10
    size=$1
    title "Test ping flood $size"
    if [ -n "$size" ]; then
        size="-s $size"
    fi
    ping 7.7.7.2 -f -c $COUNT $size -w $TIMEOUT > $TMP1 &
    ping 7.7.7.2 -f -c $COUNT $size -w $TIMEOUT > $TMP2 &
    ping 7.7.7.2 -f -c $COUNT $size -w $TIMEOUT > $TMP3 &
    wait
    err=0
    for i in 1 2 3; do
        count1=`egrep -o "[0-9]+ received" /tmp/ping$i | cut -d" " -f1`
        if [ -z $count1 ]; then
            err "ping$i: Cannot read ping output"
            err=1
        elif [[ $count1 -ne $COUNT ]]; then
            err "ping$i: Received $count1 packets, expected $COUNT"
            err=1
        fi
    done
    if [[ $err == 0 ]]; then
        success
    fi
    rm -fr $TMP1
    rm -fr $TMP2
    rm -fr $TMP3
}

test_ping_flood
test_ping_flood 32768

cleanup
test_done
