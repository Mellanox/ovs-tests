#!/bin/bash
#
# Test OVS with geneve + dec_ttl + mirror
#
# Bug SW #3628698: [ASAP, OFED 23.10, k8] Encap geneve rule not offloaded with geneve_opts + ttl + mirroring
#
# Require external server

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_remote_server

IP=1.1.1.7
REMOTE=1.1.1.8

LOCAL_TUN=7.7.7.7
REMOTE_IP=7.7.7.8
TUN_ID=42
geneve_port=6081
VXLAN_ID=$TUN_ID

TUNNEL_TEST=geneve
#TUNNEL_TEST=vxlan

config_sriov 2
enable_switchdev
unbind_vfs
bind_vfs
require_interfaces REP NIC VF


function cleanup_remote() {
    on_remote "ip a flush dev $REMOTE_NIC
               ip l del dev geneve1 &>/dev/null
               ip link del vm &>/dev/null
               ip l del dev vxlan1 &>/dev/null"
}

function cleanup() {
    start_clean_openvswitch
    ip -all netns delete
    ip a flush dev $NIC
    reset_tc $NIC $VF $REP
    cleanup_remote
    sleep 0.5
}
trap cleanup EXIT

function config() {
    cleanup
    ip link set $NIC up
    ip netns add ns0
    ip link set dev $VF netns ns0
    ip netns exec ns0 ifconfig $VF $IP/24 up
    ip link set $REP up
    ip link set $REP2 up

    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs $REP2
    ovs-vsctl -- --id=@p1 get port $REP2 -- \
                 --id=@m create mirror name=m1 select-all=true output-port=@p1 -- \
                 set bridge br-ovs mirrors=@m || err "Failed to set mirror port"
    ovs-vsctl add-br vlan_tunnel1
    ovs-vsctl add-port vlan_tunnel1 $NIC
    ifconfig vlan_tunnel1 $LOCAL_TUN/24 up

    if [ "$TUNNEL_TEST" == "geneve" ]; then
        ovs-vsctl add-port br-ovs geneve1 -- set interface geneve1 type=geneve options:local_ip=$LOCAL_TUN options:remote_ip=$REMOTE_IP options:key=$TUN_ID options:dst_port=$geneve_port
        local tun=geneve1
        local extra="set_field:0x1234->tun_metadata0,"
        ovs-ofctl add-tlv-map br-ovs "{class=0xffff,type=0x80,len=4}->tun_metadata0"
    else
        ovs-vsctl add-port br-ovs vxlan1 -- set interface vxlan1 type=vxlan options:local_ip=$LOCAL_TUN options:remote_ip=$REMOTE_IP options:key=$VXLAN_ID options:dst_port=4789 options:csum=true
        local tun=vxlan1
        local extra=""
    fi

    ovs-ofctl add-flow br-ovs arp,actions=normal
    ovs-ofctl add-flow br-ovs "ip,in_port=$tun,actions=${extra}dec_ttl,output:$REP" || fail "Failed adding openflow rule"
    ovs-ofctl add-flow br-ovs "ip,in_port=$REP,actions=${extra}dec_ttl,output:$tun" || fail "Failed adding openflow rule"
    ovs-vsctl show
    ovs-ofctl dump-flows --color br-ovs
}

function run() {
    config
    if [ "$TUNNEL_TEST" == "geneve" ]; then
        config_remote_geneve_options
    else
        config_remote_vxlan
    fi
    sleep 1

    # icmp
    ip netns exec ns0 ping -q -c 1 -w 1 $REMOTE
    if [ $? -ne 0 ]; then
        err "ping failed"
        return
    fi

    timeout 3 tcpdump -qnnei $REP -c 10 ip &
    local tpid1=$!
    sleep 1

    ip netns exec ns0 ping -q -c 10 -i 0.1 -w 2 $REMOTE || err "ping failed"

    title "Verify rules"
    local out=`ovs_dump_flows -m | grep 0x0800 | grep -v "offloaded:yes"`
    if [ -n "$out" ]; then
        err "Unoffloaded flows"
        echo $out
    fi

    title "Verify offload"
    verify_no_traffic $tpid1
}

run
test_done
