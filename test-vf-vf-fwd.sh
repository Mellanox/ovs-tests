#!/bin/bash
#
# Test traffic while adding ofctl fwd and drop rules.
#
# Bug SW #1241076: Hit WARN_ON when adding many rules with different mask
# Bug SW #1438051: [Ofed 4.4] Hit WARN_ON when adding fwd and drop rules while traffic is going
# Bug SW #1486319: [Upstream] possible deadlock when adding fwd and drop rules while traffic is going
# Bug SW #1506941: [upstream] null deref in validate_xmit_skb_list()
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

IP1="7.7.7.1"
IP2="7.7.7.2"

ROUNDS=${ROUNDS:-10}
let TIMEOUT=ROUNDS*90

function cleanup() {
    killall -q -9 iperf3
    wait &>/dev/null
    ovs_clear_bridges
    ip netns del ns0 2> /dev/null
    ip netns del ns1 2> /dev/null
}
trap cleanup EXIT

cleanup

enable_switchdev
unbind_vfs
set_eswitch_inline_mode_transport
bind_vfs

require_interfaces VF VF2 REP REP2
start_clean_openvswitch
config_vf ns0 $VF $REP $IP1
config_vf ns1 $VF2 $REP2 $IP2

BR=ov1
ovs-vsctl add-br $BR
ovs-vsctl add-port $BR $REP
ovs-vsctl add-port $BR $REP2

title "Test ping $VF($IP1) -> $VF2($IP2)"
ip netns exec ns0 ping -q -c 10 -i 0.2 -w 4 $IP2 && success || err "ping failed"

title "Test iperf $VF($IP1) -> $VF2($IP2)"
killall -9 iperf3 &>/dev/null
timeout $TIMEOUT ip netns exec ns1 iperf3 -s --one-off -i 0 -D >/dev/null
sleep 1
timeout $TIMEOUT ip netns exec ns0 iperf3 -c $IP2 -t $((TIMEOUT-10)) -B $IP1 -P 100 --cport 6000 -i 0 >/dev/null &
sleep 1

ovs-ofctl add-flow $BR "dl_dst=11:11:11:11:11:11,actions=drop"

# WA: sometimes ovs-ofctl fails to connect to ovs-vswitchd socket so try again.
# ovs-ofctl: ov1: failed to connect to socket (Broken pipe)
function ovs-ofctl1() {
    local arg=$@
    ovs-ofctl $arg || ovs-ofctl $arg
}

for r in `seq $ROUNDS`; do
    if ! pidof iperf3 $>/dev/null ; then
        err "iperf is not running"
    fi
    if [ $TEST_FAILED == 1 ]; then
        killall -9 iperf3
        break
    fi
    title "- round $r/$ROUNDS"
    sleep 2
    title "- add fwd rules above 6000"
    for i in {6110..6500..1}; do
        ovs-ofctl1 add-flow $BR "in_port=$REP,tcp,tcp_src=$i,actions=output:$REP2" || err "adding ofctl rule"
    done
    sleep 2
    title "- add fwd rules from 6000"
    for i in {6000..6098..2}; do
        ovs-ofctl1 add-flow $BR "in_port=$REP,tcp,tcp_src=$i,actions=output:$REP2" || err "adding ofctl rule"
    done
    sleep 2
    title "- add drop rules"
    for i in {6000..6100..2}; do
        ovs-ofctl1 add-flow $BR "in_port=$REP,tcp,tcp_src=$i,actions=drop" || err "adding ofctl rule"
    done
    sleep 2
    title "- clear rules"
    ovs-ofctl del-flows $BR tcp
done

trap - EXIT
cleanup
test_done
