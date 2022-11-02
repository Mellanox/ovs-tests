#!/bin/bash
#
# Test OVS CT with geneve options traffic
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
TUN_ID=42

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
    on_remote "ip a flush dev $REMOTE_NIC
               ip l del dev geneve1 &>/dev/null
               ip link del vm &>/dev/null"
}

function cleanup() {
    ip a flush dev $NIC
    ip netns del ns0 &>/dev/null
    ip netns del ns1 &>/dev/null
    cleanup_remote
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
    ip netns exec ns0 ifconfig $VF $IP/24 mtu 1200 up

    echo "Restarting OVS"
    start_clean_openvswitch

    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs geneve1 -- set interface geneve1 type=geneve options:local_ip=$LOCAL_TUN options:remote_ip=$REMOTE_IP options:key=$TUN_ID options:dst_port=6081
}

function config_remote() {
    local geneve_opts="geneve_opts ffff:80:00001234"

    config_remote_geneve external

    title "Setup remote geneve + opts"
    on_remote "ip link add vm type veth peer name vm_rep
               ifconfig vm $REMOTE/24 up
               ifconfig vm_rep 0 promisc up
               tc qdisc add dev vm_rep ingress
               tc filter add dev vm_rep ingress proto ip flower skip_hw action tunnel_key set src_ip 0.0.0.0 dst_ip $LOCAL_TUN id $TUN_ID dst_port 6081 $geneve_opts pipe action mirred egress redirect dev geneve1
               tc filter add dev vm_rep ingress proto arp flower skip_hw action tunnel_key set src_ip 0.0.0.0 dst_ip $LOCAL_TUN id $TUN_ID dst_port 6081 $geneve_opts pipe action mirred egress redirect dev geneve1
               tc filter add dev geneve1 ingress protocol arp flower skip_hw action tunnel_key unset action mirred egress redirect dev vm_rep
               tc filter add dev geneve1 ingress protocol ip flower skip_hw action tunnel_key unset action mirred egress redirect dev vm_rep"
}

function add_openflow_rules() {
    ovs-ofctl del-flows br-ovs
    ovs-ofctl add-flow br-ovs arp,actions=normal
    ovs-ofctl add-flow br-ovs icmp,actions=normal
    ovs-ofctl add-tlv-map br-ovs "{class=0xffff,type=0x80,len=4}->tun_metadata0"
    ovs-ofctl add-flow br-ovs "table=0, in_port=geneve1,tun_metadata0=0x1234 tcp,ct_state=-trk actions=ct(table=1)"
    ovs-ofctl add-flow br-ovs "table=1, in_port=geneve1,tcp,tun_metadata0=0x1234,ct_state=+trk+new actions=ct(commit),normal"
    ovs-ofctl add-flow br-ovs "table=1, in_port=geneve1, tcp,tun_metadata0=0x1234,ct_state=+trk+est actions=normal"
    ovs-ofctl add-flow br-ovs "table=0, in_port=$REP,tcp,ct_state=-trk actions=ct(table=1)"
    ovs-ofctl add-flow br-ovs "table=1, in_port=$REP,tcp,ct_state=+trk+new actions=set_field:0x1234->tun_metadata0,ct(commit),normal"
    ovs-ofctl add-flow br-ovs "table=1, in_port=$REP,tcp,ct_state=+trk+est actions=set_field:0x1234->tun_metadata0,normal"
    ovs-ofctl dump-flows br-ovs --color
}

function run() {
    config
    config_remote
    add_openflow_rules

    ping_remote || return

    initial_traffic

    start_traffic || return

    verify_traffic "$VF" "$REP genev_sys_6081"

    kill_traffic
}

run
ovs_clear_bridges
test_done
