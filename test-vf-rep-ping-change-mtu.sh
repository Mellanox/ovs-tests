#!/bin/bash
#
# Change VF and REP MTU during ping
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

IP1="7.7.7.1"
IP2="7.7.7.2"

enable_switchdev_if_no_rep $REP
bind_vfs

function cleanup() {
    ip netns del ns0 2> /dev/null
    sleep 0.5 # wait for VF to bind back
    ip link set $REP mtu 1500
    ip link set $VF mtu 1500
    ifconfig $REP 0
}

trap cleanup EXIT
cleanup
ifconfig $REP $IP1/24 up
ip netns add ns0
ip link set $VF netns ns0
ip netns exec ns0 ifconfig $VF $IP2/24 up

title "Test ping VF($IP2) -> REP($IP1)"
ip netns exec ns0 ping -q -f -w 10 $IP1 &
pid=$!
sleep 0.5
pidof ping &>/dev/null || fail "Ping failed"

echo "Change mtu during traffic"
for mtu in 500 1000 2000 1500 ; do
    sleep 1
    ip link set $REP mtu $mtu || fail "Failed to set mtu to $REP"
    ip netns exec ns0 ip link set $VF mtu $mtu || fail "Failed to set mtu to $VF"
done

wait $pid
rc=$?

if [ $rc != 0 ]; then
    err "Ping failed"
fi

test_done
