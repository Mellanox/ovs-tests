#!/bin/bash
#
# Bug SW #1333837: In inline-mode transport UDP fragments from VF are dropped
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

function start_tcpdump() {
    tdtmpfile=/tmp/$$.pcap
    rm -f $tdtmpfile
    tcpdump -nnepi $REP udp -c 30 -w $tdtmpfile &
    tdpid=$!
    sleep 0.5
}

function stop_tcpdump() {
    kill $tdpid 2>/dev/null
    if [ ! -f $tdtmpfile ]; then
        err "Missing tcpdump output"
    fi
}

function test_frags() {
    # match fragmented packets (not first)
    count=`tcpdump -nnr $tdtmpfile 'ip[6] = 0' | wc -l`
    if [[ $count = 0 ]]; then
        err "No fragmented packets"
        tcpdump -nnr $tdtmpfile
    else
        success
    fi
}


cleanup
ifconfig $REP $IP1/24 up
ip netns add ns0
ip link set $VF netns ns0
ip netns exec ns0 ifconfig $VF $IP2/24 up

title "Test fragmented packets REP->VF"
start_tcpdump
iperf -u -c $IP2 -b 1M -l 2000 -n 1M
stop_tcpdump
title " - verify with tcpdump"
test_frags

title "Test fragmented packets VF->REP"
start_tcpdump
ip netns exec ns0 iperf -u -c $IP1 -b 1M -l 2000 -n 1M
stop_tcpdump
title " - verify with tcpdump"
test_frags

# this should be the smallest packet that gets fragmented.
# the second fragment will be with data of size 1.
title "Test fragmented packets VF->REP 1473"
start_tcpdump
ip netns exec ns0 iperf -u -c $IP1 -b 1M -l 1473 -n 1M
stop_tcpdump
title " - verify with tcpdump"
test_frags

# the driver needs to copy udp header (8 bytes) for fragmented packet
# to match L4 inline header.
# this case is we have 7 bytes to copy and left with padding of 1.
title "Test fragmented packets VF->REP 1479"
start_tcpdump
ip netns exec ns0 iperf -u -c $IP1 -b 1M -l 1479 -n 1M
stop_tcpdump
title " - verify with tcpdump"
test_frags

cleanup
test_done
