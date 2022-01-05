#!/bin/bash
#
# Test header rewrite dnat
#
# Verify the following ovs actions
#
#   actions:set(eth(dst=76:59:99:fb:a9:bc)),set(ipv4(dst=192.168.0.2)),set(tcp(dst=5001)),ct(commit),set(ipv4(ttl=63)),enp8s0f0_0
#
# can be parsed to the right tc actions.
#
# Old ovs merges all header rewrite actions into one tc action. If there
# is a ct action between header rewrite ipv4 address and dec_ttl, the
# header rewrite action for ipv4 address will be lost.
#
# Bug SW #2894058 tc filter output is missing DNAT action at ip+16
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_remote_server

config_sriov 2
enable_switchdev
require_interfaces REP
unbind_vfs
bind_vfs
reset_tc $REP

PORT=5001
PORT_DNAT=9999
VF_IP=192.168.0.2
ROUTE_IP=192.168.0.1

REMOTE_IP=8.9.10.11
DNAT_IP=8.9.10.1

function cleanup() {
    ovs_conf_remove tc-policy &>/dev/null
    ip netns del ns0 2> /dev/null
    reset_tc $REP
    on_remote "ifconfig $REMOTE_NIC 0"
    pkill iperf
}
trap cleanup EXIT

function config_ovs() {
    title "setup ovs"
    MAC_ROUTE=24:8a:07:ad:77:99

    start_clean_openvswitch
    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs $NIC

    ovs-ofctl add-flow br-ovs "table=0, in_port=$REP, dl_type=0x0806, nw_dst=$ROUTE_IP, actions=load:0x2->NXM_OF_ARP_OP[], move:NXM_OF_ETH_SRC[]->NXM_OF_ETH_DST[], mod_dl_src=${MAC_ROUTE}, move:NXM_NX_ARP_SHA[]->NXM_NX_ARP_THA[], move:NXM_OF_ARP_SPA[]->NXM_OF_ARP_TPA[], load:0x248a07ad7799->NXM_NX_ARP_SHA[], load:0xc0a80001->NXM_OF_ARP_SPA[], in_port"
    ovs-ofctl add-flow br-ovs "table=0, in_port=$NIC, dl_type=0x0806, nw_dst=$DNAT_IP, actions=load:0x2->NXM_OF_ARP_OP[], move:NXM_OF_ETH_SRC[]->NXM_OF_ETH_DST[], mod_dl_src:${MAC_ROUTE}, move:NXM_NX_ARP_SHA[]->NXM_NX_ARP_THA[], move:NXM_OF_ARP_SPA[]->NXM_OF_ARP_TPA[], load:0x248a07ad7799->NXM_NX_ARP_SHA[], load:0x08090a01->NXM_OF_ARP_SPA[], in_port"

    VF_MAC=$(ip netns exec ns0 cat /sys/class/net/$VF/address)
    REMOTE_PF_MAC=$(ssh $REMOTE_SERVER cat /sys/class/net/$REMOTE_NIC/address)
    ovs-ofctl add-flow br-ovs "table=0,priority=10,in_port=$NIC,tcp,tp_dst=$PORT_DNAT,nw_dst=$DNAT_IP actions=mod_nw_dst:$VF_IP,mod_tp_dst:$PORT,mod_dl_dst=$VF_MAC,ct(commit),dec_ttl,$REP"
    ovs-ofctl add-flow br-ovs "table=0,priority=10,in_port=$REP,tcp,nw_src=$VF_IP,tp_src=$PORT actions=mod_nw_src:$DNAT_IP,mod_tp_src:$PORT_DNAT,mod_dl_dst=$REMOTE_PF_MAC,$NIC"
}

function config() {
    config_vf ns0 $VF $REP $VF_IP
    ip netns exec ns0 ip route add 8.9.10.0/24 via $ROUTE_IP dev $VF

    on_remote "ifconfig $REMOTE_NIC $REMOTE_IP/24"
}

function run_ovs() {
    title "Test OVS without offload"
    start_clean_openvswitch
    ovs_conf_remove hw-offload
    ovs_conf_remove tc-policy
    config_ovs

    ip netns exec ns0 pkill iperf
    ip netns exec ns0 iperf -s &
    sleep 1
    on_remote "iperf -c $DNAT_IP -p $PORT_DNAT -i 1 -t 6" &
    pid=$!

    sleep 2
    ovs_actions=$(ovs_dump_flows --names | grep commit | sed "s/.*actions:/actions:/")
    echo $ovs_actions
    if [ -z $ovs_actions ]; then
        err "dnat doesn't work for ovs"
    fi

    wait $pid
}

function run_ovs_offload() {
    title "Test OVS with tc-policy=skip_hw"
    start_clean_openvswitch
    ovs_conf_set hw-offload true
    ovs_conf_set tc-policy skip_hw
    config_ovs

    ip netns exec ns0 pkill iperf
    ip netns exec ns0 iperf -s &
    sleep 1
    on_remote "iperf -c $DNAT_IP -p $PORT_DNAT -i 1 -t 6" &
    pid=$!

    sleep 2
    tc_actions=$(ovs_dump_tc_flows --names | grep commit | sed "s/.*actions:/actions:/")
    echo $tc_actions
    if [ -z "$tc_actions" ]; then
        err "dnat doesn't work for ovs offload"
    fi

    wait $pid
}

config
run_ovs
run_ovs_offload

if [[ "$ovs_actions" == "$tc_actions" ]]; then
    success "tc actions are same as ovs actions"
else
    err "tc actions are not same as ovs actions"
fi

ovs_conf_remove tc-policy
start_clean_openvswitch
test_done
