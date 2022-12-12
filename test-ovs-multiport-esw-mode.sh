#!/bin/bash
#
# Feature Request #2327830: [YahooJ] OVS-Kernel SR-IOV PF/VF
# link status segregation for single VF/multiple PF combination for redundancy
# require LAG_RESOURCE_ALLOCATION to be enabled

my_dir="$(dirname "$0")"
. $my_dir/common.sh

min_nic_cx6dx
require_remote_server

IP="7.7.7.1"
REMOTE="7.7.7.2"
MAC="e4:11:22:11:4a:51"

function cleanup() {
    title "Cleanup"
    ovs_clear_bridges
    ip netns del ns0 &> /dev/null
    set_port_state_up &> /dev/null
    restore_lag_port_select_mode
    restore_lag_resource_allocation_mode
    fw_config KEEP_ETH_LINK_UP_P1=1 || err "Failed to configure FW"
    enable_legacy $NIC2
    config_sriov 0 $NIC2
    clear_remote_bonding
}

function get_sending_dev() {
    ovs_dump_flows --names -m | grep "0x0800" | grep "in_port($REP)" | grep -oP "actions:(\w+)"| cut -d":" -f2
}

function config_remote() {
    title "Config remote"
    remote_disable_sriov
    config_remote_bonding
    on_remote "ip a add $REMOTE/24 dev bond0"
}

function config() {
    title "Config"
    fw_config KEEP_ETH_LINK_UP_P1=0 || fail "Failed to configure FW"
    enable_lag_resource_allocation_mode
    set_lag_port_select_mode "multiport_esw"
    config_sriov 2
    config_sriov 2 $NIC2
    enable_switchdev
    enable_switchdev $NIC2
    bind_vfs $NIC
    bind_vfs $NIC2
    set_interfaces_up
    config_ovs
    add_openflow_rules
    config_remote
    reset_tc $REP
    config_vf ns0 $VF $REP $IP $MAC
}

function set_interfaces_up() {
    ip link set $NIC up
    ip link set $NIC2 up
    ip link set $VF up
    wait_for_linkup $NIC
}

function config_ovs() {
    title "Config OVS"
    start_clean_openvswitch
    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $NIC
    ovs-vsctl add-port br-ovs $NIC2
    ovs-vsctl add-port br-ovs $REP
    ovs-ofctl add-group br-ovs group_id=1,type=fast_failover,bucket=watch_port=$NIC,actions=$NIC,bucket=watch_port=$NIC2,actions=$NIC2
}

function add_openflow_rules() {
    title "Adding openflow rules"
    ovs-ofctl del-flows br-ovs
    ovs-ofctl add-flow br-ovs in_port=$NIC,arp,actions=output:$REP
    ovs-ofctl add-flow br-ovs in_port=$NIC2,arp,actions=output:$REP
    ovs-ofctl add-flow br-ovs in_port=$NIC,dl_dst=$MAC,actions=output:$REP
    ovs-ofctl add-flow br-ovs in_port=$NIC2,dl_dst=$MAC,actions=output:$REP
    ovs-ofctl add-flow br-ovs in_port=$REP,actions=group:1
}

function run_traffic() {
    ip netns exec ns0 ping -q -c 1 -i 0.1 -w 2 $REMOTE

    if [ $? -ne 0 ]; then
        err "Init traffic failed"
        return
    fi

    local t=10
    local pid_remote
    local pid_offload
    local pid_ping

    echo "Run ICMP traffic for $t seconds"
    ip netns exec ns0 ping -w $t -i 0.2 -q $REMOTE &
    pid_ping=$!

    sleep 1
    echo "Sniff packets on $REP"
    timeout $((t-1)) tcpdump -qnnei $REP -c 15 'icmp' &
    pid_offload=$!

    on_remote "timeout $t tcpdump -qnnei bond0 -c 5 'icmp'" &
    pid_remote=$!

    current_sending_dev=$(get_sending_dev)
    title "Current interface that send packets $current_sending_dev"

    title "Verify traffic on remote"
    verify_have_traffic $pid_remote

    set_port_state_down
    sleep 2

    new_sending_dev=$(get_sending_dev)
    title "Current interface that send packets $new_sending_dev"

    on_remote "timeout $t tcpdump -qnnei bond0 -c 5 'icmp'" &
    pid_remote=$!

    title "Verify traffic on remote port1 down"
    verify_have_traffic $pid_remote

    wait $pid_ping
    local rc=$?

    if [ $rc -ne 0 ]; then
        err "ICMP traffic failed"
    fi

    title "Verify that the sending nic is changed after setting $NIC down"

    if [[ $current_sending_dev == $new_sending_dev ]]; then
        err "Expected traffic to be sent on different nic"
    fi

    title "Verify traffic offload on $REP"
    verify_no_traffic $pid_offload

    ovs_clear_bridges
    set_port_state_up
}

trap cleanup EXIT

config
run_traffic
trap - EXIT
cleanup
test_done
