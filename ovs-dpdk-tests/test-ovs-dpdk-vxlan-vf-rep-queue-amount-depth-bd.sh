#!/bin/bash
#
# Test OVS with vxlan traffic with minimal VF and REP queue amount and depth
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

IP=1.1.1.7
REMOTE=1.1.1.8

LOCAL_TUN=7.7.7.7
REMOTE_IP=7.7.7.8
VXLAN_ID=42

declare -A queue_config_min=(
    ['vf_channels']=1
    ['vf_rq_size']=64
    ['vf_sq_size']=64
    ['rep_channels']=1
    ['rep_rq_size']=64
    ['rep_sq_size']=64
)

vf_channels_path=/sys/module/mlx5_core/parameters/pre_probe_vf_num_of_channels
vf_rq_size_path=/sys/module/mlx5_core/parameters/pre_probe_vf_rq_size
vf_sq_size_path=/sys/module/mlx5_core/parameters/pre_probe_vf_sq_size

rep_channels_path=/sys/class/net/$NIC/pre_init_rep_num_of_channels
rep_rq_size_path=/sys/class/net/$NIC/pre_init_rep_rq_size
rep_sq_size_path=/sys/class/net/$NIC/pre_init_rep_sq_size

if [ ! -f "$vf_channels_path" ] || [ ! -f "$vf_rq_size_path" ] || \
     [ ! -f "$vf_sq_size_path" ] || [ ! -f "$rep_channels_path" ] || \
     [ ! -f "$rep_rq_size_path" ] || [ ! -f "$rep_sq_size_path" ]; then
     fail "can not access VF/REP queue config"
fi

function set_queue_amount_depth() {
    echo "$1" > $vf_channels_path
    echo "$2" > $vf_rq_size_path
    echo "$3" > $vf_sq_size_path
    echo "$4" > $rep_channels_path
    echo "$5" > $rep_rq_size_path
    echo "$6" > $rep_sq_size_path
}

function reset_queue_defaults() {
    title "Resetting queue config to defaults"
    set_queue_amount_depth 0 0 0 0 0 0
}

function cleanup_remote() {
    on_remote ip a flush dev $REMOTE_NIC
    on_remote ip l del dev vxlan1 &>/dev/null
}

function cleanup() {
    reset_queue_defaults
    start_clean_openvswitch
    ip a flush dev $NIC
    ip netns del ns0 &>/dev/null
    cleanup_e2e_cache
    cleanup_remote
    sleep 0.5
}
trap cleanup EXIT

function config() {
    title "Config local"
    config_sriov 2
    enable_switchdev
    require_interfaces REP NIC
    unbind_vfs
    bind_vfs
    cleanup
    set_queue_amount_depth ${queue_config_min['vf_channels']} ${queue_config_min['vf_rq_size']} ${queue_config_min['vf_sq_size']} ${queue_config_min['rep_channels']} ${queue_config_min['rep_rq_size']} ${queue_config_min['rep_sq_size']}
    debug "Restarting OVS"
    start_clean_openvswitch

    config_simple_bridge_with_rep 0
    config_remote_bridge_tunnel $VXLAN_ID $REMOTE_IP
    config_local_tunnel_ip $LOCAL_TUN br-phy
    config_ns ns0 $VF $IP
}

function config_remote() {
    title "Config remote"
    on_remote ip link del vxlan1 &>/dev/null
    on_remote ip link add vxlan1 type vxlan id $VXLAN_ID remote $LOCAL_TUN dstport 4789
    on_remote ip a flush dev $REMOTE_NIC
    on_remote ip a add $REMOTE_IP/24 dev $REMOTE_NIC
    on_remote ip a add $REMOTE/24 dev vxlan1
    on_remote ip l set dev vxlan1 up
    on_remote ip l set dev $REMOTE_NIC up
}

function add_openflow_rules() {
    ovs-ofctl dump-flows br-int --color
}

function run() {
    # Traffic test
    config
    config_remote
    add_openflow_rules

    title "Checking traffic offload"
    # icmp
    ip netns exec ns0 ping -q -c 1 -w 1 $REMOTE
    if [ $? -ne 0 ]; then
        err "ping failed"
        return
    fi

    t=15
    # traffic
    ip netns exec ns0 timeout $((t+2)) iperf3 -s &
    pid1=$!
    sleep 2
    on_remote timeout $((t+2)) iperf3 -c $IP -t $t &
    pid2=$!

    # verify pid
    sleep 2
    kill -0 $pid2 &>/dev/null
    if [ $? -ne 0 ]; then
        err "iperf3 failed"
        return
    fi

    sleep $((t-4))
    # check offloads
    check_dpdk_offloads $IP

    kill -9 $pid1 &>/dev/null
    killall iperf3 &>/dev/null
    debug "wait for bgs"
    wait
}

run
trap - EXIT
cleanup
test_done
