function config_remote_bridge_tunnel() {
    local vni=$1
    local remote_ip=$2
    local tnl_type=${3:-vxlan}
    local reps=${4:-1}

    ovs-vsctl --may-exist add-br br-int   -- set Bridge br-int datapath_type=netdev   -- br-set-external-id br-int bridge-id br-int   -- set bridge br-int fail-mode=standalone
    ovs-vsctl add-port br-int ${tnl_type}0   -- set interface ${tnl_type}0 type=${tnl_type} options:key=${vni} options:remote_ip=${remote_ip}

    for (( i=0; i<$reps; i++ ))
    do
        ovs-vsctl add-port br-int rep$i -- set Interface rep$i type=dpdk options:dpdk-devargs=$PCI,representor=[$i]
    done
}

function config_simple_bridge_with_rep() {
    local reps=$1
    ovs-vsctl --may-exist add-br br-phy -- set Bridge br-phy datapath_type=netdev -- br-set-external-id br-phy bridge-id br-phy -- set bridge br-phy fail-mode=standalone
    ovs-vsctl add-port br-phy pf -- set Interface pf type=dpdk options:dpdk-devargs=$PCI

    for (( i=0; i<$reps; i++ ))
    do
        ovs-vsctl add-port br-phy rep$i -- set Interface rep$i type=dpdk options:dpdk-devargs=$PCI,representor=[$i]
    done
}

function config_local_tunnel_ip() {
    local ip_addr=$1
    local dev=$2

    ip addr add $ip_addr/24 dev $dev
    ip link set $dev up
}

function config_static_arp_ns() {
    local ns=$1
    local ns2=$2
    local dev=$3
    local ip_addr=$4

    ip netns exec $ns ip link set $dev address e4:11:22:33:44:50
    ip netns exec $ns2 arp -s $ip_addr e4:11:22:33:44:50
}

function config_ns() {
    local ns=$1
    local dev=$2
    local ip_addr=$3

    ip netns add $ns
    ip link set $dev netns $ns
    ip netns exec $ns ifconfig $dev $ip_addr up
}

function set_e2e_cache_enable() {
    local enabled=${1:-true}
    ovs-vsctl --no-wait set Open_vSwitch . other_config:e2e-enable=${enabled}
}

function cleanup_e2e_cache() {
    ovs-vsctl --no-wait remove Open_vSwitch . other_config e2e-enable
}

function check_dpdk_offloads() {
    local IP=$1

    local x=$(ovs-appctl dpctl/dump-flows -m | grep -v 'ipv6\|icmpv6\|arp\|drop\|ct_state(0x21/0x21)\|flow-dump' | grep -- $IP'\|tnl_pop' | wc -l)
    echo -e "Number of filtered rules:\n$x"
    local y=$(ovs-appctl dpctl/dump-flows -m type=offloaded | grep -v 'ipv6\|icmpv6\|arp\|drop\|flow-dump' | wc -l)
    echo -e "Number of offloaded rules:\n$y"
    if [ $x -ne $y ]; then
        err "offloads failed"
        echo "Filtered rules:"
        ovs-appctl dpctl/dump-flows -m | grep -v 'ipv6\|icmpv6\|arp\|drop\|ct_state(0x21/0x21)\|flow-dump' | grep -- $IP'\|tnl_pop'
        echo -e "\n\nOffloaded rules:"
        ovs-appctl dpctl/dump-flows -m type=offloaded | grep -v 'ipv6\|icmpv6\|arp\|flow-dump'
    fi
}

function del_openflow_rules() {
    local bridge=$1

    ovs-ofctl del-flows $bridge
    sleep 1
}

function check_offloaded_connections() {
    local num_of_connections=$1

    local x=$(ovs-appctl dpctl/offload-stats-show | grep 'Total  CT bi-dir Connections:' | awk '{print $5}')
    if [ $x -lt $num_of_connections ]; then
        err "No offloaded connections created, expected $num_of_connections, got $x"
    fi
}
