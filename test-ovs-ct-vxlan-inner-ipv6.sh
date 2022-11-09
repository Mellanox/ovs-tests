#!/bin/bash
#
# Test OVS CT with vxlan traffic. inner traffic ipv6
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-ovs-ct.sh

require_module act_ct
require_remote_server

IP="2001:0db8:0:f101::1"
REMOTE="2001:0db8:0:f101::2"

LOCAL_TUN=7.7.7.7
REMOTE_IP=7.7.7.8
VXLAN_ID=42

# make sure port2 is not configured in switchdev as we could have issue when
# both ports configured. we have test-ovs-ct-vxlan-2.sh and test-ovs-ct-vxlan-3.sh
# to verify with both ports configured.
enable_legacy $NIC2
config_sriov 0 $NIC2
config_sriov 2
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

function cleanup() {
    ip a flush dev $NIC
    ip netns del ns0 &>/dev/null
    ip netns del ns1 &>/dev/null
    cleanup_remote_vxlan
    sleep 0.5
}
trap cleanup EXIT

function config() {
    cleanup
    set_nf_liberal
    conntrack -F
    ifconfig $NIC $LOCAL_TUN/24 up
    # WA SimX bug? interface not receiving traffic from tap device to down&up to fix it.
    for i in $NIC $VF $REP ; do
            ifconfig $i down
            ifconfig $i up
            reset_tc $i
    done
    ip netns add ns0
    ip link set dev $VF netns ns0
    ip netns exec ns0 ip addr add dev $VF $IP/64
    ip netns exec ns0 ip link set dev $VF up

    echo "Restarting OVS"
    start_clean_openvswitch

    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs vxlan1 -- set interface vxlan1 type=vxlan options:local_ip=$LOCAL_TUN options:remote_ip=$REMOTE_IP options:key=$VXLAN_ID options:dst_port=4789
}

function add_openflow_rules() {
    ovs-ofctl del-flows br-ovs
    ovs-ofctl add-flow br-ovs arp,actions=normal
    ovs-ofctl add-flow br-ovs icmp,actions=normal
    ovs-ofctl add-flow br-ovs icmp6,actions=normal
    ovs-ofctl add-flow br-ovs "table=0, ip6,ct_state=-trk actions=ct(table=1)"
    ovs-ofctl add-flow br-ovs "table=1, ip6,ct_state=+trk+new actions=ct(commit),normal"
    ovs-ofctl add-flow br-ovs "table=1, ip6,ct_state=+trk+est actions=normal"
    ovs-ofctl dump-flows br-ovs --color
}

function run() {
    config
    config_remote_vxlan
    add_openflow_rules
    sleep 2

    ping_remote || return

    initial_traffic

    start_traffic || return

    verify_traffic "$VF" "$REP vxlan_sys_4789"

    kill_traffic
}

run
ovs-vsctl del-br br-ovs
trap - EXIT
cleanup
test_done
