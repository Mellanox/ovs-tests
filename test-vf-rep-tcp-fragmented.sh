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

function config_ipv4() {
    title "Config IPv4"
    cleanup
    IP1="7.7.7.1"
    IP2="7.7.7.2"
    ifconfig $REP $IP1/24 up
    ip netns add ns0
    ip link set $VF netns ns0
    ip netns exec ns0 ifconfig $VF $IP2/24 up
}

function run_cases() {
    title "Test fragmented packets VF->REP"
    timeout 2 tcpdump -nnepi $REP -c 1 'tcp && ip[6]!=0 && ip[7]!=0' &
    pid=$!
    ip netns exec ns0 /usr/bin/python -c 'from scapy.all import * ; send( fragment(IP(dst="7.7.7.1")/TCP()/("X"*60000)) )'
    wait $pid
    rc=$?
    if [[ $rc -eq 0 ]]; then
        success
    else
        err
    fi
}


config_ipv4
run_cases
test_done
