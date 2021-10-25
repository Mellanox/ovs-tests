#!/bin/bash
#
# Test SF traffic with TTL Open flow rules.
#
# [MLNX OFED] Bug SW #2685132: [OFED 5.4, SFs] mlx5dr_domain_cache_get_recalc_cs_ft_addr call trace and kernel panic over ETH SR-IOV ASAP Vxlan Tunnel Traffic over SF

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-sf.sh

require_remote_server

IP="7.7.7.1"
REMOTE="7.7.7.2"

function set_eswitch_ipv4_ttl_modify_enable() {
    if [ "$short_device_name" == "cx6dx" ]; then
        return
    fi

    local mode=$1
    title "set_eswitch_ipv4_ttl_modify_enable value to $mode"
    fw_config ESWITCH_IPV4_TTL_MODIFY_ENABLE=$mode || fail "Cannot set eswitch ipv4 ttl modify to $mode"
    fw_reset
    config_sriov 2
    enable_switchdev
}

function cleanup() {
    remove_ns
    ovs_clear_bridges
    remove_sfs
    cleanup_remote
    set_eswitch_ipv4_ttl_modify_enable false
}

function remove_ns() {
    ip netns del ns0 &> /dev/null
}

function cleanup_remote() {
    on_remote ip a flush dev $REMOTE_NIC
}

trap cleanup EXIT

function config() {
    title "Config"
    set_eswitch_ipv4_ttl_modify_enable true

    create_sfs 1
    fail_if_err "Failed to create sfs"

    start_clean_openvswitch
    config_remote

    title "SFs Netdev Rep Info"
    SF=`sf_get_netdev 1`
    SF_REP=`sf_get_rep 1`
    echo "SF: $SF, REP: $SF_REP"

    ip link set dev $NIC up
    config_vf ns0 $SF $SF_REP $IP
    config_ovs
}

function config_remote() {
    on_remote "ip a flush dev $REMOTE_NIC
               ip a add $REMOTE/24 dev $REMOTE_NIC
               ip l set dev $REMOTE_NIC up"
}

function config_ovs() {
    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $SF_REP
    ovs-vsctl add-port br-ovs $NIC
    ovs-ofctl del-flows br-ovs
    ovs-ofctl add-flow br-ovs "arp,action=normal"
    ovs-ofctl add-flow br-ovs "in_port=$SF_REP,ip actions=dec_ttl,output:$NIC"
    ovs-ofctl add-flow br-ovs "in_port=$NIC,ip actions=dec_ttl,output:$SF_REP"
}

function run_traffic() {
    t=15
    echo "run traffic for $t seconds"
    on_remote timeout $((t+1)) iperf -s &
    sleep 1
    ip netns exec ns0 timeout $((t-1)) iperf -t $t -c $REMOTE -P 3 &

    sleep 2
    pidof iperf &>/dev/null || err "iperf failed"

    echo "sniff packets on $SF_REP"
    timeout $((t-4)) tcpdump -qnnei $SF_REP -c 10 'tcp' &
    pid1=$!

    sleep $t
    killall -9 iperf &>/dev/null
    wait $! 2>/dev/null

    title "test traffic offload"
    verify_no_traffic $pid1
}

enable_norep_switchdev $NIC
config
run_traffic
cleanup
trap - EXIT
test_done
