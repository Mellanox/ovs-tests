#!/bin/bash
#
# Test OVS CT icmp traffic over MTU
#
# Bug SW #1774992: [CT] frag packets not passing with ct rules

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module act_ct

IP1="7.7.7.1"
IP2="7.7.7.2"

enable_switchdev
require_interfaces REP REP2
unbind_vfs
bind_vfs
reset_tc $REP
reset_tc $REP2

function cleanup() {
    ip netns del ns0 2> /dev/null
    ip netns del ns1 2> /dev/null
    reset_tc $REP
    reset_tc $REP2
}
trap cleanup EXIT

function run() {
    title "Test OVS CT ICMP"
    config_vf ns0 $VF $REP $IP1
    config_vf ns1 $VF2 $REP2 $IP2

    echo "setup ovs"
    start_clean_openvswitch
    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs $REP2

    ovs-ofctl add-flow br-ovs in_port=$REP,dl_type=0x0806,actions=output:$REP2
    ovs-ofctl add-flow br-ovs in_port=$REP2,dl_type=0x0806,actions=output:$REP

    ovs-ofctl add-flow br-ovs "table=0, icmp,ct_state=-trk actions=ct(table=1)"
    ovs-ofctl add-flow br-ovs "table=1, icmp,ct_state=+trk+new actions=ct(commit),normal"
    ovs-ofctl add-flow br-ovs "table=1, icmp,ct_state=+trk+est actions=normal"

    ovs-ofctl dump-flows br-ovs --color

    echo "run traffic"
    ip netns exec ns0 ping -q -c 10 -i 0.1 -w 2 $IP2 -s 2000 || err "Ping failed"

    # current ovs with workaround to pass to tc ct rules with frag flag.
    # so don't check for tc rules and don't check for offload.

    ovs-vsctl del-br br-ovs
}


run
test_done
