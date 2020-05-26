#!/bin/bash
#
# Test VF Mirror basic VF1->VF2,VF3 with mirrors on same and different nics
#
# Bug SW #1718378: [upstream] syndrome (0x563e2f) followed by kernel panic during VF mirroring under stress traffic.
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

IP1="7.7.7.1"
IP2="7.7.7.2"

require_interfaces NIC NIC2
config_sriov 3
config_sriov 1 $NIC2
enable_switchdev_if_no_rep $REP
enable_switchdev $NIC2
REP3=`get_rep 2`
REP4=`get_rep 0 $NIC2`
require_interfaces REP REP2 REP3 REP4
unbind_vfs
unbind_vfs $NIC2
bind_vfs
bind_vfs $NIC2
VF3=`get_vf 2`
VF4=`get_vf 0 $NIC2`
reset_tc $REP
reset_tc $REP2
require_interfaces VF VF2 VF3 VF4

mac1=`cat /sys/class/net/$VF/address`
mac2=`cat /sys/class/net/$VF2/address`

test "$mac1" || fail "no mac1"
test "$mac2" || fail "no mac2"

function cleanup() {
    ip netns del ns0 2> /dev/null
    ip netns del ns1 2> /dev/null
    reset_tc $REP
    reset_tc $REP2
}
trap cleanup EXIT

function run() {
    reset_tc $REP $REP2
    title $1
    vf_mirror=$2
    mirror=$3
    ifconfig $vf_mirror 0 up
    ifconfig $mirror 0 up

    echo "add arp rules"
    tc_filter add dev $REP ingress protocol arp prio 1 flower \
        action mirred egress redirect dev $REP2

    tc_filter add dev $REP2 ingress protocol arp prio 1 flower \
        action mirred egress redirect dev $REP

    echo "add vf mirror rules"
    tc_filter add dev $REP ingress protocol ip prio 2 flower skip_sw \
        dst_mac $mac2 \
        action mirred egress mirror dev $mirror pipe \
        action mirred egress redirect dev $REP2

    tc_filter add dev $REP2 ingress protocol ip prio 2 flower skip_sw \
        dst_mac $mac1 \
        action mirred egress mirror dev $mirror pipe \
        action mirred egress redirect dev $REP

    fail_if_err

    echo $REP
    tc filter show dev $REP ingress

    echo "sniff packets on $vf_mirror"
    timeout 2 tcpdump -qnei $vf_mirror -c 6 'icmp' &
    pid=$!

    echo "run traffic"
    ip netns exec ns0 ping -q -c 10 -i 0.1 -w 2 $IP2 || err "Ping failed"

    wait $pid
    # test sniff timedout
    rc=$?
    if [[ $rc -eq 0 ]]; then
        success
    elif [[ $rc -eq 124 ]]; then
        err "No mirrored packets"
    else
        err "Tcpdump failed"
    fi
}

config_vf ns0 $VF $REP $IP1
config_vf ns1 $VF2 $REP2 $IP2

run "Test VF mirror, with mirror on same nic." $VF3 $REP3
run "Test VF mirror, with mirror on different nic." $VF4 $REP4
test_done
