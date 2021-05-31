#!/bin/bash
#
# Test vf-rep traffic in both ports
#
# vf-rep traffic failed if both ports were in switchdev mode in socket direct nic.
# this reproduced with metadata vport matching.
# RE: SF# 00941564 : 'CX6DX ASAP2: ASAP2 failure in CX6DX 1X100G Socket-direct NIC'
#
# Bug SW #2669739: [socket direct] vf-rep traffic not working on port2 if both ports in switchdev

my_dir="$(dirname "$0")"
. $my_dir/common.sh

IP1="7.7.7.1"
IP2="7.7.7.2"

disable_sriov
enable_sriov
enable_switchdev
enable_switchdev $NIC2
bind_vfs $NIC
bind_vfs $NIC2

VF1_NIC2=`get_vf 0 $NIC2`
REP1_NIC2=`get_rep 0 $NIC2`

require_interfaces VF REP VF1_NIC2 REP1_NIC2

function cleanup() {
    ip netns del ns0 2> /dev/null
    ip addr flush dev $REP &>/dev/null
    ip addr flush dev $REP1_NIC2 &>/dev/null
}
trap cleanup EXIT

cleanup
title "Test ping on port1 $REP($IP1) -> $VF($IP2)"
config_vf ns0 $VF $REP $IP2
ifconfig $REP $IP1/24 up
ping -q -c 10 -i 0.2 -w 4 $IP2 && success || err

cleanup
title "Test ping port2 $REP1_NIC2($IP1) -> $VF1_NIC2($IP2)"
config_vf ns0 $VF1_NIC2 $REP1_NIC2 $IP2
ifconfig $REP1_NIC2 $IP1/24 up
ping -q -c 10 -i 0.2 -w 4 $IP2 && success || err

cleanup
disable_sriov_port2
test_done
