#!/bin/bash
#
# Bug SW #1333837: In inline-mode transport UDP fragments from VF are dropped
#

NIC=${1:-ens5f0}
VF=${2:-ens5f2}
REP=${3:-ens5f0_0}
my_dir="$(dirname "$0")"
. $my_dir/common.sh

enable_switchdev_if_no_rep $REP
unbind_vfs
set_eswitch_inline_mode_transport
bind_vfs

function cleanup() {
    ip netns del ns0 2> /dev/null
    ip addr flush dev $REP
}
trap cleanup EXIT

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
    sync
}

function test_frags() {
    # match fragmented packets (not first)
    if [ "$_test" == "ipv4" ]; then
        count=`tcpdump -nnr $tdtmpfile 'ip[6] = 0' | wc -l`
    elif [ "$_test" == "ipv4vlan" ]; then
        count=`tcpdump -nnr $tdtmpfile 'vlan 2 && ip[6] = 0' | wc -l`
    elif [ "$_test" == "ipv6" ]; then
        count=`tcpdump -nnr $tdtmpfile 'ip6[6] = 44' | wc -l`
    else
        fail "Mssing _test value"
    fi

    if [[ $count = 0 ]]; then
        err "No fragmented packets"
        tcpdump -nnr $tdtmpfile
    else
        success
    fi

    rm -fr $tdtmpfile
}

function config_ipv4() {
    title "Config IPv4"
    cleanup
    IP1="7.7.7.1"
    IP2="7.7.7.2"
    ifconfig $REP $IP1/24 up
    ip netns add ns0
    ip link set $VF netns ns0
    ip netns exec ns0 ifconfig $VF $IP2/24 up
    _test="ipv4"
    iperf_ext=""
}

function config_ipv4_vlan() {
    title "Config IPv4 VLAN"
    cleanup
    IP1="7.7.7.1"
    IP2="7.7.7.2"
    ifconfig $REP $IP1/24 up
    ip netns add ns0
    VF_VLAN=${VF}.2
    ip link set $VF netns ns0
    ip netns exec ns0 vconfig add $VF 2
    ip netns exec ns0 ifconfig $VF up
    ip netns exec ns0 ifconfig $VF_VLAN $IP2/24 up
    ip netns exec ns0 ip n add $IP1 dev $VF_VLAN lladdr ae:99:98:22:73:14
    _test="ipv4vlan"
    iperf_ext=""
}

function config_ipv6() {
    title "Config IPv6"
    cleanup
    IP1="2001:0db8:0:f101::1"
    IP2="2001:0db8:0:f101::2"
    ifconfig $REP inet6 add $IP1/64 up || fail "Failed to config ipv6"
    ip netns add ns0
    ip link set $VF netns ns0
    ip netns exec ns0 ifconfig $VF inet6 add $IP2/64 up || fail "Failed to config ipv6"
    _test="ipv6"
    iperf_ext="-V"
    # ipv6 assignment seems to take some time.
    # if we try iperf really quick we get an error:
    # connect failed: Cannot assign requested address
    sleep 2
}

function run_cases() {
    title "Test fragmented packets VF->REP"
    start_tcpdump
    ip netns exec ns0 iperf -u -c $IP1 -b 1M -l 2000 -n 1M $iperf_ext
    stop_tcpdump
    title " - verify with tcpdump"
    test_frags

    # this should be the smallest packet that gets fragmented.
    # the second fragment will be with data of size 1.
    title "Test fragmented packets VF->REP 1473"
    start_tcpdump
    ip netns exec ns0 iperf -u -c $IP1 -b 1M -l 1473 -n 1M $iperf_ext
    stop_tcpdump
    title " - verify with tcpdump"
    test_frags

    # the driver needs to copy udp header (8 bytes) for fragmented packet
    # to match L4 inline header.
    # this case is we have 7 bytes to copy and left with padding of 1.
    title "Test fragmented packets VF->REP 1479"
    start_tcpdump
    ip netns exec ns0 iperf -u -c $IP1 -b 1M -l 1479 -n 1M $iperf_ext
    stop_tcpdump
    title " - verify with tcpdump"
    test_frags
}


config_ipv4
run_cases

config_ipv4_vlan
run_cases

config_ipv6
run_cases

test_done
