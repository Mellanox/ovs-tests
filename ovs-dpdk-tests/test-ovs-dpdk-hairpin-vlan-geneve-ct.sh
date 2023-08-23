#!/bin/bash
#
# Test OVS-DOCA Hairpin with geneve, vlan and CT
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

config_sriov 2
enable_switchdev
require_interfaces REP NIC
bind_vfs

trap cleanup EXIT

function cleanup() {
    cleanup_test
    on_remote_exec "cleanup_test"
    on_remote "rm -rf $p_server
               rm -rf $p_client
               ip link delete ${REMOTE_NIC}_vlan 2>/dev/null"
}

function add_openflow_rules() {
    local bridge="br-phy"

    ovs-ofctl add-flow $bridge "in_port=ib_pf0, tcp action=br-phy-patch"
    ovs-ofctl add-flow $bridge "in_port=vtap-br-phy, action=push_vlan:0x8100 mod_vlan_vid:5,ib_pf0" -O OpenFlow11
    ovs-ofctl add-flow $bridge "in_port=br-phy-patch, action=ib_pf0"
    ovs-ofctl add-flow $bridge "in_port=ib_pf0,udp dl_vlan=5 action=pop_vlan,vtap-br-phy"
    ovs-ofctl add-flow $bridge "in_port=ib_pf0,arp dl_vlan=5 action=pop_vlan,vtap-br-phy"

    debug "$bridge openflow rules"
    ovs-ofctl dump-flows $bridge --color
}

function add_ct_rules() {
    local bridge=${1:-"br-int"}
    local proto=${2:-"tcp"}
    local in_port=${3:-"geneve_br-int"}
    local out_port=${4:-"br-int-patch"}

    ovs-ofctl add-flow $bridge "table=0,in_port=$in_port,$proto,ct_state=-trk,actions=ct(zone=5, table=1)"
    ovs-ofctl add-flow $bridge "table=1,in_port=$in_port,$proto,ct_state=+trk+new,actions=ct(zone=5, commit),$out_port"
    ovs-ofctl add-flow $bridge "table=1,in_port=$in_port,$proto,ct_state=+trk+est,ct_zone=5,actions=$out_port"
    ovs-ofctl add-flow $bridge "table=0,in_port=$out_port,$proto,ct_state=-trk,actions=ct(zone=5, table=1)"
    ovs-ofctl add-flow $bridge "table=1,in_port=$out_port,$proto,ct_state=+trk+new,actions=ct(zone=5, commit),$in_port"
    ovs-ofctl add-flow $bridge "table=1,in_port=$out_port,$proto,ct_state=+trk+est,ct_zone=5,actions=$in_port"

    debug "$bridge openflow rules"
    ovs-ofctl dump-flows $bridge --color
}

function add_patch_port() {
    local bridge=$1
    local peer_bridge=$2

    ovs-vsctl -- add-port $bridge "${bridge}-patch" -- set interface "${bridge}-patch" type=patch options:peer="${peer_bridge}-patch"
}

function add_vtap_port() {
    local bridge=${1:-"br-phy"}
    local vtap_port=${2:-"vtap-br-phy"}

    ovs-vsctl add-port $bridge $vtap_port -- set interface $vtap_port type=internal
    ifconfig $vtap_port $LOCAL_TUN_IP/24 up
}

function config_remote() {
    local vlan_id=5
    local vlan_dev="${REMOTE_NIC}_vlan"

    config_remote_tunnel "geneve"
    on_remote "ip netns add ns0
               ip l set dev $TUNNEL_DEV netns ns0
               ip netns exec ns0 ifconfig $TUNNEL_DEV $REMOTE_IP/24 up
               ip address flush dev $REMOTE_NIC
               ip address add dev $REMOTE_NIC $LOCAL_IP/24
               ip link add link $REMOTE_NIC name $vlan_dev type vlan id $vlan_id
               ip address add dev $vlan_dev $REMOTE_TUNNEL_IP/24
               ip link set dev $vlan_dev up"
}

function config() {
    config_simple_bridge_with_rep 0
    config_remote_bridge_tunnel $TUNNEL_ID $REMOTE_TUNNEL_IP geneve 0
    add_vtap_port
    add_patch_port br-int br-phy
    add_patch_port br-phy br-int
    config_remote
    add_ct_rules
    add_openflow_rules
}

function run_traffic() {
    local ip=$1
    local namespace=$2
    local client_dst_execution="ip netns exec $namespace"

    local t=5

    sleep_time=$((t+2))

    # server
    on_remote "rm -rf $p_server"
    local server_cmd="timeout $sleep_time $iperf_cmd -f Mbits -s -D --logfile $p_server"

    debug "Executing | on_remote $server_cmd"
    on_remote "$server_cmd"

    sleep 2

    # client
    on_remote "rm -rf $p_client"
    local client_cmd="${client_dst_execution} $iperf_cmd -f Mbits -c $ip -t $t -P $num_connections --logfile $p_client"

    debug "Executing | on_remote $client_cmd"
    on_remote "$client_cmd"

    verify_iperf_running remote
    validate_offload $ip
    on_remote_exec validate_actual_traffic
    stop_traffic
}

function run_test() {
    cleanup
    config
    run_traffic $LOCAL_IP ns0
}

run_test
trap - EXIT
cleanup
test_done
