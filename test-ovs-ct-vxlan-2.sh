#!/bin/bash
#
# Test OVS CT with vxlan traffic
#
# Bug 1824795: [ASAP-BD, Connection tracking]: Traffic failed to be offloaded on recv side (different hosts) (wont fix)
# Bug SW #1827703: CT VXLAN traffic decap is not offloaded
#
# Uplink reps register to egdev_all
# last port registers will be on top
# on vxlan decap without egress action, like ct+goto chain,
# we will call egdev_all and the first on the list
# is the last port registered but we might run traffic
# on the first port. so miniflow->priv is incorrect.
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-ovs-ct.sh

require_module act_ct
require_remote_server

IP=1.1.1.7
REMOTE=1.1.1.8

LOCAL_TUN=7.7.7.7
REMOTE_IP=7.7.7.8
VXLAN_ID=42

function config_ports() {
    # config first port
    config_sriov 2
    enable_switchdev
    require_interfaces REP NIC
    unbind_vfs
    bind_vfs

    # config second port second to be first on the list
    config_sriov 0 $NIC2
    config_sriov 1 $NIC2
    enable_switchdev $NIC2
    reset_tc $NIC2
}

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
    config_sriov 0 $NIC2
    ip a flush dev $NIC
    ip netns del ns0 &>/dev/null
    ip netns del ns1 &>/dev/null
    ovs_clear_bridges
    reset_tc $REP
    cleanup_remote_vxlan
    sleep 0.5
}
trap cleanup EXIT

function config() {
    cleanup
    config_ports
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
    ip netns exec ns0 ifconfig $VF $IP/24 up

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
    ovs-ofctl add-flow br-ovs "table=0, tcp,ct_state=-trk actions=ct(table=1)"
    ovs-ofctl add-flow br-ovs "table=1, tcp,ct_state=+trk+new actions=ct(commit),normal"
    ovs-ofctl add-flow br-ovs "table=1, tcp,ct_state=+trk+est actions=normal"
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
