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
require_interfaces VF REP

function cleanup() {
    if ip netns ls | grep -q -w ns0; then
        ip -netns ns0 link set dev $VF netns 1
        ip netns del ns0
    fi
    ip link set $VF mtu 1500
    ip link set $REP mtu 1500
    ifconfig $REP 0
}

trap cleanup EXIT
cleanup

config_vf ns0 $VF $REP $IP2
ifconfig $REP $IP1/24 up

title "Test ping VF($IP2) -> REP($IP1)"
ip netns exec ns0 ping -q -f -w 6 $IP1 &
pid=$!
sleep 1
pidof ping &>/dev/null || fail "Ping failed"

echo "Change mtu during traffic"
for mtu in 500 1000 1500 2000; do
    echo "set mtu $mtu"
    ip link set $REP mtu $mtu || fail "Failed to set mtu to $REP"
    ip netns exec ns0 ip link set $VF mtu $mtu || fail "Failed to set mtu to $VF"
    sleep 1
done

wait $pid
rc=$?

if [ $rc != 0 ]; then
    err "Ping failed"
fi

trap - EXIT
cleanup
test_done
