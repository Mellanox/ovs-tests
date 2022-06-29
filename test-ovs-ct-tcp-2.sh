#!/bin/bash
#
# Test OVS CT tcp to remote server
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-ovs-ct.sh

require_module act_ct
require_remote_server

IP="7.7.7.1"
REMOTE="7.7.7.2"

enable_switchdev
require_interfaces REP NIC
unbind_vfs
bind_vfs

function set_nf_liberal() {
    nf_liberal="/proc/sys/net/netfilter/nf_conntrack_tcp_be_liberal"
    if [ -e $nf_liberal ]; then
        echo 1 > $nf_liberal
        echo "`basename $nf_liberal` set to: `cat $nf_liberal`"
    else
        echo "Cannot find $nf_liberal"
    fi
}

function cleanup_remote() {
    on_remote ip a flush dev $REMOTE_NIC
}

function cleanup() {
    ip a flush dev $NIC
    ip netns del ns0 &>/dev/null
    cleanup_remote
    sleep 0.5
}
trap cleanup EXIT

function config() {
    cleanup
    set_nf_liberal
    conntrack -F
    # WA SimX bug? interface not receiving traffic from tap device to down&up to fix it.
    for i in $NIC $VF $REP ; do
            ip link set $i down
            ip link set $i up
            reset_tc $i
    done
    ip addr flush dev $NIC
    ip link set dev $NIC up
    ip netns add ns0
    ip link set dev $VF netns ns0
    ip netns exec ns0 ip a add $IP/24 dev $VF
    ip netns exec ns0 ip link set dev $VF up

    echo "Restarting OVS"
    start_clean_openvswitch

    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs $NIC
}

function config_remote() {
    on_remote "ip a flush dev $REMOTE_NIC
               ip a add $REMOTE/24 dev $REMOTE_NIC
               ip l set dev $REMOTE_NIC up"
}

function add_openflow_rules() {
    ovs-ofctl del-flows br-ovs
    ovs-ofctl add-flow br-ovs arp,actions=normal
    ovs-ofctl add-flow br-ovs icmp,actions=normal
    ovs-ofctl add-flow br-ovs "table=0, in_port=$REP,ip,ct_state=-trk actions=ct(table=1)"
    ovs-ofctl add-flow br-ovs "table=1, in_port=$REP,ip,ct_state=+trk+new actions=ct(commit),normal"
    ovs-ofctl add-flow br-ovs "table=1, in_port=$REP,ip,ct_state=+trk+est actions=normal"

    ovs-ofctl add-flow br-ovs "table=0, in_port=$NIC,ip,ct_state=-trk actions=ct(table=1)"
    ovs-ofctl add-flow br-ovs "table=1, in_port=$NIC,ip,ct_state=+trk+est actions=normal"
    ovs-ofctl dump-flows br-ovs --color
}

function run() {
    config
    config_remote
    add_openflow_rules

    ping_remote || return

    initial_traffic

    start_traffic || return

    verify_traffic "$VF" "$REP $NIC"

    kill_traffic
}

run
ovs-vsctl del-br br-ovs
cleanup
trap - EXIT
test_done
