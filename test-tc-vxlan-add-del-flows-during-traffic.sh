#!/bin/bash
#
# Test deleting/adding TC vxlan rules with TCP traffic going in BG.
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_remote_server

IP=1.1.1.7
REMOTE=1.1.1.8

LOCAL_TUN=7.7.7.7
REMOTE_IP=7.7.7.8
VXLAN_ID=42
DSTPORT=4789

function cleanup() {
    ip netns del ns0 &>/dev/null
    reset_tc $REP
    ip link del vxlan1 &>/dev/null
    ip a flush dev $NIC
    cleanup_remote_vxlan
    sleep 0.5
}
trap cleanup EXIT

function config_local() {
    title "Config vxlan"
    ip link add name vxlan1 type vxlan dstport $DSTPORT external
    for i in $REP vxlan1; do
            ifconfig $i up
            reset_tc $i
    done
    ifconfig $NIC $LOCAL_TUN/24 up
    config_vf ns0 $VF $REP $IP
}

function add_vxlan_rules() {
    local proto=$1
    local encap_prio=$2
    local decap_prio=$3
    local ip_proto_match=""

    echo "- Add vxlan rules (proto=$proto, encap_prio=$encap_prio, decap_prio=$decap_prio)"
    if [ "$proto" = "tcp" ]; then
        proto="ip"
        ip_proto_match="ip_proto tcp"
    fi

    # encap rule for packets from local to remote
    tc_filter add dev $REP protocol $proto parent ffff: prio $encap_prio flower $ip_proto_match \
        action tunnel_key set \
        src_ip $LOCAL_TUN     \
        dst_ip $REMOTE_IP     \
        dst_port $DSTPORT     \
        id $VXLAN_ID          \
        action mirred egress redirect dev vxlan1

    # decap rule for packets from remote to local
    tc_filter add dev vxlan1 protocol $proto parent ffff: prio $decap_prio flower $ip_proto_match \
        enc_src_ip $REMOTE_IP   \
        enc_dst_ip $LOCAL_TUN   \
        enc_dst_port $DSTPORT   \
        enc_key_id $VXLAN_ID    \
        action tunnel_key unset \
        action mirred egress redirect dev $REP
}

function del_vxlan_rules() {
    local proto=$1
    local encap_prio=$2
    local decap_prio=$3

    echo "- Del vxlan rules (proto=$proto, encap_prio=$encap_prio, decap_prio=$decap_prio)"
    tc_filter del dev $REP ingress protocol $proto prio $encap_prio flower
    tc_filter del dev vxlan1 ingress protocol $proto prio $decap_prio flower
}

function check_ping() {
    title "ping traffic"
    ip netns exec ns0 ping -q -c 1 -w 1 $REMOTE
    if [ $? -ne 0 ]; then
        err "ping failed!"
        return 1
    fi
}

function run() {
    title "Add vxlan rules"
    add_vxlan_rules arp 1 1
    add_vxlan_rules tcp 2 3
    add_vxlan_rules ip  4 5

    check_ping || return

    t=60
    end=$((SECONDS+$t))

    ip netns exec ns0 timeout $((t-4)) tcpdump -qnnei $VF -c 30 'tcp' &
    traffic_pid=$!

    # Traffic
    on_remote timeout $((t+2)) iperf3 -s -D

    ip netns exec ns0 timeout $((t+1)) iperf3 -c $REMOTE -t $t -P8 &
    iperf_pid=$!

    # Verify pid
    kill -0 $iperf_pid &>/dev/null
    if [ $? -ne 0 ]; then
        err "iperf3 failed!"
        return
    fi

    timeout $((t-4)) tcpdump -qnnei $REP -c 10 'tcp' &
    offload_pid=$!

    # Delete/Add vxlan rules
    while [ $SECONDS -lt $end ]; do
        del_vxlan_rules ip  2 3
        add_vxlan_rules tcp 2 3
    done

    title "Verify traffic on $VF"
    verify_have_traffic $traffic_pid

    title "Verify no traffic on $REP"
    verify_no_traffic $offload_pid

    killall -9 -q iperf3 &>/dev/null
    on_remote killall -9 -q iperf3 &>/dev/null
    echo "Wait for bgs"
    wait
}

config_sriov
enable_switchdev
require_interfaces REP NIC
bind_vfs

cleanup
config_local
config_remote_vxlan
sleep 2
run

trap - EXIT
cleanup

test_done
