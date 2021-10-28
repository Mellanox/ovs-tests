#!/bin/bash
#
# Test OVS-DPDK with geneve traffic
# while having TLV option having OVS-DPDK on both sides to cover
# cases which geneve tunnel is not supported by kernel
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/../common.sh
. $my_dir/common-dpdk.sh

require_remote_server

IP=1.1.1.7
REMOTE=1.1.1.8

LOCAL_TUN=7.7.7.7
REMOTE_IP=7.7.7.8
GENEVE_ID=42

function cleanup() {
    local exec_on_remote=${1:-false}
    local cmd="ip a flush dev $NIC; \
               ip netns del ns0 &>/dev/null; \
               "
    local restart_cmd="ovs_clear_bridges; \
                       stop_openvswitch; \
                       service_ovs start; \
                       "

    if [ "$exec_on_remote" = true ]; then
        title "Cleaning up remote"
        on_remote ovs-vsctl clear open_vswitch . other_config
        on_remote_dt "$cmd"
        on_remote_dt "$restart_cmd"
    else
        title "Cleaning up local"
        cleanup_e2e_cache
        eval "$cmd"
        start_clean_openvswitch
    fi
}

function cleanup_exit() {
    cleanup false
    cleanup true
}

function config() {
    local exec_on_remote=${1:=false}
    local wanted_remote_ip=$2
    local wanted_local_ip=$3
    local vf_ip=$4
    local cmd="config_sriov 2; \
               require_interfaces REP NIC; \
               unbind_vfs; \
               bind_vfs; \
               set_e2e_cache_enable false; \
               start_clean_openvswitch; \
               config_simple_bridge_with_rep 0; \
               config_remote_bridge_tunnel $GENEVE_ID $wanted_remote_ip geneve; \
               config_local_tunnel_ip $wanted_local_ip br-phy; \
               config_ns ns0 $VF $vf_ip; \
               ip netns exec ns0 ifconfig $VF mtu 1400
               "

    if [ "$exec_on_remote" = true ]; then
        title "Configuring remote server"
        on_remote_dt "$cmd"
        on_remote_dt ovs_conf_set hw-offload false
    else
        title "Configuring local server"
        cleanup false
        eval "$cmd"
    fi
}

function config_openflow_rules() {
    local exec_on_remote=${1:-false}
    local cmd="ovs-ofctl add-tlv-map br-int \"{class=0xffff,type=0x80,len=4}->tun_metadata0\"; \
               ovs-ofctl del-flows br-int; \
               ovs-ofctl add-flow br-int arp,actions=normal; \
               ovs-ofctl add-flow br-int \"priority=1,arp,actions=normal\"; \
               ovs-ofctl add-flow br-int \"in_port=rep0,actions=set_field:0x1234->tun_metadata0,normal\"; \
               ovs-ofctl add-flow br-int \"tun_metadata0=0x1234,actions=normal\"; \
               ovs-ofctl dump-flows br-int --color; \
               "

    if [ "$exec_on_remote" = true ]; then
        on_remote_dt "$cmd"
    else
        eval "$cmd"
    fi
}

function run() {
    config false $REMOTE_IP $LOCAL_TUN $IP
    config true $LOCAL_TUN $REMOTE_IP $REMOTE
    config_openflow_rules false
    config_openflow_rules true

    echo -e "Testing ping"
    ip netns exec ns0 ping -q -c 5 $REMOTE -w 7
    if [ $? -ne 0 ]; then
        err "ping failed"
        return
    fi

    echo -e "\nTesting TCP traffic"
    t=15
    # traffic
    ip netns exec ns0 timeout $((t+2)) iperf3 -s &
    pid1=$!
    sleep 2
    on_remote timeout $((t+2)) ip netns exec ns0 iperf3 -c $IP -t $t &
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
    echo "wait for bgs"
    wait
}

run
cleanup_exit
test_done
