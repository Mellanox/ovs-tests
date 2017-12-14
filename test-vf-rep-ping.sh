#!/bin/bash
#
# Bug SW #1040416: slow path xmit on VF reps broken
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
}

cleanup
ifconfig $REP $IP1/24 up
ip netns add ns0
ip link set $VF netns ns0
ip netns exec ns0 ifconfig $VF $IP2/24 up

title "Test ping REP($IP1) -> VF($IP2)"
ping -q -c 10 -i 0.2 -w 2 $IP2 && success || err

title "Test ping VF($IP2) -> REP($IP1)"
ip netns exec ns0 ping -q -c 10 -i 0.2 -w 2 $IP1 && success || err

cleanup
test_done
