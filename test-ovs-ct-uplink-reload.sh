#!/bin/bash
#
# Test reload module where this is ct tuples still offloaded on uplink rep
#
# Bug SW: #3009705: [NGN-Signed][CT] Call Traces Observed While Cleaning CT Rules (mlx5_ct_fs_smfs_destroy+0x24/0x30)
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh
pktgen=$my_dir/scapy-traffic-tester.py

require_module act_ct

IP1="7.7.7.1"
IP2="7.7.7.2"

enable_switchdev
require_interfaces REP REP2
unbind_vfs
bind_vfs
reset_tc $REP
reset_tc $REP2
reset_tc $NIC

function cleanup() {
    ip netns del ns0 2> /dev/null
    ip netns del ns1 2> /dev/null
    reset_tc $REP &>/dev/null
    reset_tc $REP2 &>/dev/null
    reset_tc $NIC &>/dev/null
}
trap cleanup EXIT

function config_ovs() {
    local proto=$1

    echo "setup ovs"
    start_clean_openvswitch
    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs $REP2

    ovs-ofctl add-flow br-ovs in_port=$REP,dl_type=0x0806,actions=output:$REP2
    ovs-ofctl add-flow br-ovs in_port=$REP2,dl_type=0x0806,actions=output:$REP

    ovs-ofctl add-flow br-ovs "table=0, $proto,ct_state=-trk actions=ct(table=1)"
    ovs-ofctl add-flow br-ovs "table=1, $proto,ct_state=+trk+new actions=ct(commit),normal"
    ovs-ofctl add-flow br-ovs "table=1, $proto,ct_state=+trk+est actions=normal"

    ovs-ofctl dump-flows br-ovs --color
}

function run() {
    title "Test OVS CT UDP"
    config_vf ns0 $VF $REP $IP1
    config_vf ns1 $VF2 $REP2 $IP2

    proto="udp"
    config_ovs $proto

    #During module unload, vf reps do netdev_unregister() causing tc block, and then tc ct rules to be deleted before cleaning up ct
    #Uplink doesn't, so add uplink rule to hold a ref to ct zone 0 during cleanup, causing the cited bug
    tc_filter add dev $NIC ingress prio 2 chain 0 proto ip flower dst_mac aa:bb:cc:dd:ee:ff ct_state -trk action ct pipe action goto chain 1 || err "Failed adding uplink tc rule"

    t=4
    echo "run traffic for $t seconds"
    ip netns exec ns1 $pktgen -l -i $VF2 --src-ip $IP1 --time $((t+1)) &
    pk1=$!
    sleep 1
    ip netns exec ns0 $pktgen -i $VF1 --src-ip $IP1 --dst-ip $IP2 --time $t &
    pk2=$!

    sleep $t
    kill $pk1 &>/dev/null
    wait $pk1 $pk2 2>/dev/null

    ovs-vsctl del-br br-ovs
    sleep 1
    reload_modules
    config_sriov 2
}


run
test_done
