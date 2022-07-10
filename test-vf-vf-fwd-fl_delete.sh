#!/bin/bash
#
# Test fl_classify (caused by traffic) while add/del hw rules.
#
# Bug SW #1297803: [ASAP MLNX OFED] fl_classify might access invalid memory on err flow in fl_change
# Bug SW #1428435: [OFED 4.4] [rhel7.2] test-vf-vf-fwd-fl_delete.sh cause a cpu lockup
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

IP1="7.7.7.1"
IP2="7.7.7.2"

function cleanup() {
    reset_tc $REP $REP2
    ip netns del ns0 2> /dev/null
    ip netns del ns1 2> /dev/null
    sleep 1
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

tc filter add dev $REP ingress protocol arp flower skip_hw action mirred egress redirect dev $REP2 || fail "tc - failed adding arp rule"
tc filter add dev $REP2 ingress protocol arp flower skip_hw action mirred egress redirect dev $REP || fail "tc - failed adding arp rule"

tc filter add dev $REP ingress protocol ip prio 1 handle 1 flower skip_hw dst_mac aa:bb:cc:dd:ee:ff action mirred egress redirect dev $REP2 || fail "tc - failed adding fake rule"
tc filter add dev $REP2 ingress protocol ip prio 1 handle 1 flower skip_hw dst_mac aa:bb:cc:dd:ee:ff action mirred egress redirect dev $REP || fail "tc - failed adding fake rule"

tc filter add dev $REP2 ingress protocol ip prio 1 handle 2 flower skip_sw dst_mac $mac1 action mirred egress redirect dev $REP || fail "tc - failed adding correct rule"

echo "generate batch file"
cnt=100000
for i in `seq $cnt`; do
    echo filter add dev $REP ingress protocol ip prio 1 handle 2 flower skip_hw dst_mac $mac2 action mirred egress redirect dev $REP2
    echo filter del dev $REP ingress protocol ip prio 1 handle 2 flower
done > /tmp/tc_batch_1234

title "Test ping $VF($IP1, $mac1) -> $VF2($IP2, $mac2)"
ip netns exec ns0 ping -q -f $IP2 &
sleep 1
echo "apply batch file"
tc -b /tmp/tc_batch_1234 || err "tc batch failed"
killall -9 ping &>/dev/null
wait &>/dev/null

echo "cleanup"
rm -f /tmp/tc_batch_1234
cleanup
# wait for refcnt
for i in `seq 6`; do
    count1=`cat /sys/module/cls_flower/refcnt`
    count2=`cat /sys/module/act_mirred/refcnt`
    if [ "$count1" == "0" ] && [ "$count2" == "0" ]; then
        break
    fi
    sleep 1
done
# reload modules
modprobe -rv act_mirred cls_flower || err "failed unload"
modprobe -a act_mirred cls_flower
test_done
