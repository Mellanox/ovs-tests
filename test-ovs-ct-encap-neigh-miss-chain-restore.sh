#!/bin/bash
#
# Test chain restore with OVS CT nat vxlan traffic while deleting neigh so packet
# goes to slow path
#
# Bug SW #3192521: [Upstream] Encap slow path restarts from chain 0 instead of chain of tc rule
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
SNAT_IP=1.1.1.20

LOCAL_TUN=7.7.7.7
REMOTE_IP=7.7.7.8
VXLAN_ID=42

# make sure port2 is not configured in switchdev as we could have issue when
# both ports configured. we have test-ovs-ct-vxlan-2.sh and test-ovs-ct-vxlan-3.sh
# to verify with both ports configured.
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
    ovs_clear_bridges
    reset_tc $REP
    cleanup_remote_vxlan
    ovs_conf_remove max-idle
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
    ip netns exec ns0 ifconfig $VF $IP/24 up

    echo "Restarting OVS"
    start_clean_openvswitch

    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs vxlan1 -- set interface vxlan1 type=vxlan options:local_ip=$LOCAL_TUN options:remote_ip=$REMOTE_IP options:key=$VXLAN_ID options:dst_port=4789

    ovs_conf_set max-idle 100000 #to catch wrong rule
}

function add_openflow_rules() {
    ovs-ofctl del-flows br-ovs
    ovs-ofctl add-flow br-ovs arp,actions=normal
    ovs-ofctl add-flow br-ovs icmp,actions=normal
    ovs-ofctl add-flow br-ovs "table=0, tcp,ct_state=-trk nw_src=$SNAT_IP, actions=drop"
    ovs-ofctl add-flow br-ovs "table=0, tcp,ct_state=-trk nw_src=1.1.1.8, actions=ct(table=1,nat)"
    ovs-ofctl add-flow br-ovs "table=0, tcp,ct_state=-trk nw_src=1.1.1.7, actions=ct(table=1,nat)"
    ovs-ofctl add-flow br-ovs "table=1, tcp,ct_state=+trk+new actions=ct(commit,nat(src=$SNAT_IP)),normal"
    ovs-ofctl add-flow br-ovs "table=1, tcp,ct_state=+trk+est actions=normal"
    ovs-ofctl dump-flows br-ovs --color
}

function run() {
    config
    config_remote_vxlan
    add_openflow_rules
    sleep 2

    ping_remote || return

    local mac=`ip netns exec ns0 cat /sys/class/net/$VF/address`
    on_remote ip n r $SNAT_IP dev vxlan1 lladdr $mac

    initial_traffic

    echo "setting neigh update after 8 seconds"
    sleep 8 && ip n r $REMOTE_IP dev $NIC lladdr aa:bb:cc:dd:ee:ff &

    start_traffic || return

    #wait for neigh update
    sleep 10

    title "dump-flows:"
    ovs_dump_flows --names | grep 0800

    title "check for trap rule hit (wrong restore)"
    ovs_dump_flows --names | grep 0800 | grep "recirc_id(0)" | grep -i --color "src=1.1.1.20" && err "found trap rule on recirc_id(0)"

    kill_traffic
}

run
ovs-vsctl del-br br-ovs
test_done
