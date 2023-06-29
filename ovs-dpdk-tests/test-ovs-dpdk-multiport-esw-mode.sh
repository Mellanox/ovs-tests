#!/bin/bash
#
# require LAG_RESOURCE_ALLOCATION to be enabled

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

min_nic_cx6dx
require_remote_server

IP=$LOCAL_IP
REMOTE=$REMOTE_IP
MAC="e4:11:22:11:4a:51"

function keep_link_up() {
    local val=$1
    local conf="KEEP_ETH_LINK_UP_P1"

    fw_config $conf=$val || err "Failed to configure $conf=$val"
    fw_reset
}

function cleanup() {
    title "Cleanup"
    ovs_clear_bridges
    reset_tc $NIC $NIC2 $REP
    clear_remote_bonding
    ip netns del ns0 &> /dev/null
    set_port_state_up &> /dev/null
    disable_esw_multiport
    restore_lag_port_select_mode
    restore_lag_resource_allocation_mode
    keep_link_up 1
    enable_legacy $NIC2
    config_sriov 0 $NIC2
}

function get_sending_dev() {
    local REP=$IB_PF0_PORT0

    ovs_dump_flows --names | grep "0x0800" | grep "in_port($REP)" | grep -oP "actions:(\w+)"| cut -d":" -f2
}

function config_remote() {
    title "Config remote"
    remote_disable_sriov
    config_remote_bonding
    on_remote "ip a add $REMOTE/24 dev bond0"
}

function config() {
    title "Config"
    keep_link_up 0
    enable_lag_resource_allocation_mode
    set_lag_port_select_mode "multiport_esw"
    config_sriov 2
    config_sriov 2 $NIC2
    enable_switchdev
    enable_switchdev $NIC2
    enable_esw_multiport
    bind_vfs $NIC
    bind_vfs $NIC2
    set_interfaces_up
    config_ovs
    add_openflow_rules
    config_remote
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
    config_simple_bridge_with_rep 1
    ovs-vsctl add-port br-phy p1 -- set interface p1 type=dpdk options:dpdk-devargs="0000:08:00.0,dv_xmeta_en=4,dv_flow_en=2,representor=pf1"
    ovs-vsctl show
}

function add_openflow_rules() {
    local PF=`get_port_from_pci`
    local REP=$IB_PF0_PORT0

    ovs-ofctl add-group br-phy group_id=1,type=fast_failover,bucket=watch_port=$PF,actions=$PF,bucket=watch_port=p1,actions=p1
    title "Adding openflow rules"
    ovs-ofctl del-flows br-phy
    ovs-ofctl add-flow br-phy in_port=$PF,arp,actions=output:$REP
    ovs-ofctl add-flow br-phy in_port=p1,arp,actions=output:$REP
    ovs-ofctl add-flow br-phy in_port=$PF,dl_dst=$MAC,actions=output:$REP
    ovs-ofctl add-flow br-phy in_port=p1,dl_dst=$MAC,actions=output:$REP
    ovs-ofctl add-flow br-phy in_port=$REP,actions=group:1

    debug "OVS groups:"
    ovs-ofctl dump-groups br-phy --color
    debug "OVS flow rules:"
    ovs-ofctl dump-flows br-phy --color
}

function run_traffic() {
    ip netns exec ns0 ping -q -c 1 -i 0.1 -w 2 $REMOTE

    if [ $? -ne 0 ]; then
        err "Init traffic failed"
        return
    fi

    local t=15
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

    title "ovs dump flows"
    ovs_dump_flows --names | grep "0x0800"

    sending_dev1=$(get_sending_dev)
    title "Current interface sending packets $sending_dev1"
    [ -z "$sending_dev1" ] && err "Invalid sending dev"

    title "Verify traffic on remote"
    verify_have_traffic $pid_remote

    set_port_state_down
    sleep 2

    title "ovs dump flows"
    ovs_dump_flows --names | grep "0x0800"

    sending_dev2=$(get_sending_dev)
    title "Current interface sending packets $sending_dev2"
    [ -z "$sending_dev2" ] && err "Invalid sending dev"

    on_remote "timeout $t tcpdump -qnnei bond0 -c 5 'icmp'" &
    pid_remote=$!

    title "Verify traffic on remote after nic $sending_dev1 is down"
    verify_have_traffic $pid_remote

    wait $pid_ping
    local rc=$?

    if [ $rc -ne 0 ]; then
        err "ICMP traffic failed"
    fi

    if [[ $sending_dev1 == $sending_dev2 ]]; then
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
