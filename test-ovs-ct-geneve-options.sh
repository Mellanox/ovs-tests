#!/bin/bash
#
# Test OVS CT with geneve options traffic
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module act_ct

REMOTE_SERVER=${REMOTE_SERVER:-$1}
REMOTE_NIC=${REMOTE_NIC:-$2}

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
    on_remote ip a flush dev $REMOTE_NIC
    on_remote ip l del dev geneve1 &>/dev/null
    on_remote ip link del vm &>/dev/null
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
    on_remote ip link del geneve1 &>/dev/null
    on_remote ip link add geneve1 type geneve dstport 6081 external
    on_remote ip a flush dev $REMOTE_NIC
    on_remote ip a add $REMOTE_IP/24 dev $REMOTE_NIC
    on_remote ip l set dev geneve1 up
    on_remote ip l set dev $REMOTE_NIC up
    on_remote tc qdisc add dev geneve1 ingress

    title "Setup remote geneve + opts"
    on_remote ip link add vm type veth peer name vm_rep
    on_remote ifconfig vm $REMOTE/24 up
    on_remote ifconfig vm_rep 0 promisc up
    on_remote tc qdisc add dev vm_rep ingress
    on_remote tc filter add dev vm_rep ingress proto ip flower skip_hw action tunnel_key set src_ip 0.0.0.0 dst_ip $LOCAL_TUN id $TUN_ID dst_port 6081 $geneve_opts pipe action mirred egress redirect dev geneve1
    on_remote tc filter add dev vm_rep ingress proto arp flower skip_hw action tunnel_key set src_ip 0.0.0.0 dst_ip $LOCAL_TUN id $TUN_ID dst_port 6081 $geneve_opts pipe action mirred egress redirect dev geneve1
    on_remote tc filter add dev geneve1 ingress protocol arp flower skip_hw action tunnel_key unset action mirred egress redirect dev vm_rep
    on_remote tc filter add dev geneve1 ingress protocol ip flower skip_hw action tunnel_key unset action mirred egress redirect dev vm_rep

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
    #ip a show dev $NIC
    #ip netns exec ns0 ip a s dev $VF

    # icmp
    ip netns exec ns0 ping -q -c 1 -w 1 $REMOTE
    if [ $? -ne 0 ]; then
        err "ping failed"
        return
    fi

    # initial traffic
    ssh2 $REMOTE_SERVER timeout 4 iperf3 -s &
    pid1=$!
    sleep 1
    ip netns exec ns0 timeout 3 iperf3 -c $REMOTE -t 2 &
    pid2=$!

    sleep 4
    kill -9 $pid1 $pid2 &>/dev/null
    wait $pid1 $pid2 &>/dev/null

    # traffic
    ssh2 $REMOTE_SERVER timeout 15 iperf3 -s &
    pid1=$!
    sleep 1
    ip netns exec ns0 timeout 15 iperf3 -c $REMOTE -t 14 -P3 &
    pid2=$!

    # verify pid
    sleep 2
    kill -0 $pid2 &>/dev/null
    if [ $? -ne 0 ]; then
        err "iperf failed"
        return
    fi

    # verify traffic
    ip netns exec ns0 timeout 12 tcpdump -qnnei $VF -c 30 ip &
    tpid1=$!
    timeout 12 tcpdump -qnnei $REP -c 10 ip &
    tpid2=$!
    timeout 12 tcpdump -qnnei genev_sys_6081 -c 10 ip &
    tpid3=$!

    sleep 15
    title "Verify traffic on $VF"
    verify_have_traffic $tpid1
    title "Verify offload on $REP"
    verify_no_traffic $tpid2
    title "Verify offload on genev_sys_6081"
    verify_no_traffic $tpid3

    kill -9 $pid1 $pid2 &>/dev/null
    echo "wait for bgs"
    wait &>/dev/null
}

run
start_clean_openvswitch
test_done
