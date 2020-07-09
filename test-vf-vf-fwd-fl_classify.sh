#!/bin/bash
#
# Test fl_classify (caused by traffic) while adding failed hw rules.
# Bug SW #1297803: [ASAP MLNX OFED] fl_classify might access invalid memory on err flow in fl_change
#

NIC=${1:-ens2f0}
VF=${2:-ens2f2}
REP=${3:-eth0}
my_dir="$(dirname "$0")"
. $my_dir/common.sh

function relevant_kernel() {
    local v1=`uname -r | tr ._- " " | awk {'print $1'}`
    local v2=`uname -r | tr ._- " " | awk {'print $2'}`
    if [ $v1 -gt 4 ] || [ $v2 -gt 10 ]; then
        fail "Test relevant for kernel <= 4.10"
    fi
}

relevant_kernel

IP1="7.7.7.1"
IP2="7.7.7.2"

pingpid=0

function killping() {
    if [ "$pingpid" != "0" ]; then
        kill -9 $pingpid &>/dev/null
        wait $pingpid &>/dev/null
    fi
}

function cleanup() {
    killping
    reset_tc $REP
    reset_tc $REP2
    ip netns del ns0 2> /dev/null
    ip netns del ns1 2> /dev/null
}
trap cleanup EXIT

function clean_and_fail() {
    err $@
    cleanup
    fail
}

function config_vf() {
    local ns=$1
    local vf=$2
    local rep=$3
    local ip=$4

    echo "$ns : $vf ($ip) -> $rep"
    if [ ! -e /sys/class/net/$vf ]; then
        err "Cannot find $vf"
        return 1
    fi
    if [ ! -e /sys/class/net/$rep ]; then
        err "Cannot find $rep"
        return 1
    fi
    reset_tc $vf
    reset_tc $rep
    ifconfig $rep 0 up
    ip netns add $ns
    ip link set $vf netns $ns
    ip netns exec $ns ifconfig $vf $ip/24 up
}

enable_switchdev
unbind_vfs
bind_vfs
require_interfaces VF VF2 REP REP2
cleanup

mac1=`cat /sys/class/net/$VF/address`
mac2=`cat /sys/class/net/$VF2/address`

test "$mac1" || fail "no mac1"
test "$mac2" || fail "no mac2"

config_vf ns0 $VF $REP $IP1
config_vf ns1 $VF2 $REP2 $IP2

modprobe -av act_mirred cls_flower

tc filter add dev $REP ingress protocol arp flower action mirred egress redirect dev $REP2 || fail "tc - failed adding arp rule"
tc filter add dev $REP2 ingress protocol arp flower action mirred egress redirect dev $REP || fail "tc - failed adding arp rule"

# make sure we have flower instance ready for fl_classify to do something
tc filter add dev $REP ingress protocol ip prio 1 flower skip_hw dst_mac aa:bb:cc:dd:ee:ff action mirred egress redirect dev $REP2 || fail "tc - failed adding fake rule"
tc filter add dev $REP2 ingress protocol ip prio 1 flower skip_hw dst_mac aa:bb:cc:dd:ee:ff action mirred egress redirect dev $REP || fail "tc - failed adding fake rule"

title "Test ping $VF($IP1, $mac1) -> $VF2($IP2, $mac2)"
ip netns exec ns0 ping -q -f $IP2 &
pingpid=$!
sleep 1

# add with prio 3
tc filter add dev $REP ingress protocol ip prio 3 flower skip_sw dst_mac $mac1 action \
    mirred egress redirect dev $REP2 2>/dev/null || clean_and_fail "failed adding rule $REP->$REP2"
tc filter add dev $REP2 ingress protocol ip prio 3 flower skip_sw dst_mac $mac2 action \
    mirred egress redirect dev $REP 2>/dev/null || clean_and_fail "failed adding rule $REP2->$REP"

max=10000
for i in `seq $max`; do
    # add with prio 1 (different than above 3) to skip duplicate rule check in
    # flower and add it to rhashtable but expect to fail in hw because of existing
    # counter and flower will start error flow and free it while fl_classify
    # might use it.
    tc filter add dev $REP ingress protocol ip prio 1 flower skip_sw dst_mac $mac1 action \
        mirred egress redirect dev $REP2 &>/dev/null && err "tc expected to fail" && break
    tc filter add dev $REP2 ingress protocol ip prio 1 flower skip_sw dst_mac $mac2 action \
        mirred egress redirect dev $REP &>/dev/null && err "tc expected to fail" && break
    if (( i%500 == 0 )); then echo $i/$max ; fi
done

cleanup
# reload modules
sleep 1
modprobe -rv act_mirred cls_flower || err "failed unload"
modprobe -a act_mirred cls_flower
test_done
