#!/bin/bash
#
# Change VF and REP MTU during ping
# Bug SW #1415031: changing representor mtu can lead to crash
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

IP1="7.7.7.1"
IP2="7.7.7.2"

enable_switchdev
bind_vfs

function cleanup() {
    ip netns exec ns0 ip link set $VF mtu 1500 &>/dev/null
    ip netns del ns0 &>/dev/null
    ip link set $REP mtu 1500 &>/dev/nulll
    ifconfig $REP 0 &>/dev/null
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
