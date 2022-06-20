. ${DIR}/ovs-dpdk-tests/common-tunnel.sh
. ${DIR}/ovs-dpdk-tests/common-testing.sh

VDPA_DEV_NAME="eth2"

function set_ovs_dpdk_debug_logs () {
    local log="/var/log/openvswitch/ovs-vswitchd.log"
    if [ -f $log ]; then
        echo > $log
    fi
    ovs_set_log_levels ofproto_dpif_upcall:file:DBG dpif_netdev:file:DBG \
                      netdev_offload_dpdk:file:DBG netdev_offload:file:DBG
}

function require_dpdk() {
    if [ "${DPDK}" != "1" ]; then
        fail "Missing DPDK=1"
    fi

    if [ "${ENABLE_OVS_DEBUG}" == "1" ]; then
       set_ovs_dpdk_debug_logs
    fi
}

require_dpdk

function configure_dpdk_rep_ports() {
    local reps=$1
    local bridge=$2

    for (( i=0; i<$reps; i++ ))
    do
        if [ "${VDPA}" != "1" ]; then
            ovs-vsctl add-port $bridge rep$i -- set Interface rep$i type=dpdk options:dpdk-devargs=$PCI,representor=[$i]
        else
            local vf_num="VF"
            vf_num+=$((i+1))
            local vfpci=$(get_vf_pci ${!vf_num})
            ovs-vsctl add-port $bridge rep$i -- set Interface rep$i type=dpdkvdpa options:vdpa-socket-path=/tmp/sock$(($i+1)) options:vdpa-accelerator-devargs=$vfpci options:dpdk-devargs=$PCI,representor=[$i]
        fi
    done
}

function config_remote_bridge_tunnel() {
    local vni=$1
    local remote_ip=$2
    local tnl_type=${3:-vxlan}
    local reps=${4:-1}

    debug "configuring remote bridge tunnel type $tnl_type key $vni remote_ip $2 with $reps reps"
    ovs-vsctl --may-exist add-br br-int   -- set Bridge br-int datapath_type=netdev   -- br-set-external-id br-int bridge-id br-int   -- set bridge br-int fail-mode=standalone
    ovs-vsctl add-port br-int ${tnl_type}0   -- set interface ${tnl_type}0 type=${tnl_type} options:key=${vni} options:remote_ip=${remote_ip}

    configure_dpdk_rep_ports $reps "br-int"

}

function config_simple_bridge_with_rep() {
    local reps=$1

    debug "configuring simple bridge with $reps reps"
    ovs-vsctl --may-exist add-br br-phy -- set Bridge br-phy datapath_type=netdev -- br-set-external-id br-phy bridge-id br-phy -- set bridge br-phy fail-mode=standalone
    ovs-vsctl add-port br-phy pf -- set Interface pf type=dpdk options:dpdk-devargs=$PCI

    configure_dpdk_rep_ports $reps "br-phy"
}

function start_vdpa_vm() {
    local vm_name=${1:-$NESTED_VM_NAME1}
    local vm_ip=${2:-$NESTED_VM_IP1}
    local vm_started="false"

    if [ "${VDPA}" != "1" ]; then
        return
    fi
    local status=$(virsh list --all | grep $vm_name | awk '{ print $3 }')

    if [ "${status}" != "running" ]; then
        debug "starting VM $vm_name"
        virsh start $vm_name & >/dev/null
        for i in {0..100}
        do
            status=$(virsh list --all | grep "$vm_name" | awk '{ print $3 }')
            if [[ $status == "running" ]]; then
                for i in {0..500}
                do
                    if ping -c1 $vm_ip -w 1 &> /dev/null; then
                        vm_started="true"
                        break
                    fi
                done
                if [ "${vm_started}" == "false" ]; then
                    fail "timeout waiting for VM to start"
                    return
                fi
                success "VM $vm_name started"
                sleep 2
                return
            fi
            sleep 2
        done
    else
        success "VM $vm_name already started"
        return
    fi
    fail "could not start VM"
}

function config_local_tunnel_ip() {
    local ip_addr=$1
    local dev=$2

    ip addr add $ip_addr/24 dev $dev
    ip link set $dev up
}

function config_static_ipv6_neigh_ns() {
    local ns=$1
    local ns2=$2
    local src_dev=$3
    local dst_dev=$4
    local ip_addr=$5
    local dst_execution1="ip netns exec $ns"
    local dst_execution2="ip netns exec $ns2"

    if [ "${VDPA}" == 1 ]; then
        dst_execution1="on_vm $NESTED_VM_IP1"
        dst_execution2="on_vm $NESTED_VM_IP2"
        src_dev=$VDPA_DEV_NAME
        dst_dev=$VDPA_DEV_NAME
    fi

    local mac=$(${dst_execution1} ip l | grep -A1 "$src_dev" | grep link | cut -d ' ' -f 6)
    if [ -z "$mac" ]; then
        fail "could not get device $src_dev mac"
    fi
    local cmd1="${dst_execution2} ip -6 neigh add $ip_addr lladdr $mac dev $dst_dev"
    eval $cmd1
}

function config_static_arp_ns() {
    local ns=$1
    local ns2=$2
    local dev=$3
    local ip_addr=$4
    local dst_execution1="ip netns exec $ns"
    local dst_execution2="ip netns exec $ns2"

    if [ "${VDPA}" == 1 ]; then
        dst_execution1="on_vm $NESTED_VM_IP1"
        dst_execution2="on_vm $NESTED_VM_IP2"
        dev=$VDPA_DEV_NAME
    fi

    local mac=$(${dst_execution1} ip l | grep -A1 "$dev" | grep link | cut -d ' ' -f 6)
    local cmd1="${dst_execution2} arp -s $ip_addr $mac"
    eval $cmd1
}

function config_ns() {
    local ns=$1
    local dev=$2
    local ip_addr=$3
    local ipv6_addr=${4-"2001:db8:0:f101::1"}
    local vm_ip=$NESTED_VM_IP1

    if [ "${ns}" != "ns0" ]; then
        vm_ip=$NESTED_VM_IP2
    fi
    if [ "${VDPA}" != "1" ]; then
        debug "adding namespace $ns and attaching $dev"
        ip netns add $ns
        ip link set $dev netns $ns
        ip netns exec $ns ifconfig $dev $ip_addr/24 up
        ip netns exec $ns ip -6 address add $ipv6_addr/64 dev $dev
        local cmd="ip netns | grep $ns | wc -l"
        local num_ns=$(eval $cmd)
        if [ $num_ns -ne 1 ]; then
            err "failed to add namespace $ns"
        fi
    else
        debug "setting $VDPA_DEV_NAME ip $ip_addr on vm $vm_ip"
        on_vm $vm_ip ifconfig $VDPA_DEV_NAME $ip_addr/24 up
        on_vm $vm_ip ip -6 address add $ipv6_addr/64 dev $VDPA_DEV_NAME
    fi
}

function set_e2e_cache_enable() {
    local enabled=${1:-true}
    ovs-vsctl --no-wait set Open_vSwitch . other_config:e2e-enable=${enabled}
}

function cleanup_e2e_cache() {
    ovs-vsctl --no-wait remove Open_vSwitch . other_config e2e-enable
}

function query_sw_packets() {
    local num_of_pkts=100000

    if [[ "$short_device_name" == "cx5"* ]]; then
        num_of_pkts=350000
    fi

    debug "Expecting $num_of_pkts to reach SW"
    local pkts1=$(ovs-appctl dpif-netdev/pmd-stats-show | grep 'packets received:' | sed -n '1p' | awk '{print $3}')
    local pkts2=$(ovs-appctl dpif-netdev/pmd-stats-show | grep 'packets received:' | sed -n '2p' | awk '{print $3}')

    if [ -z "$pkts1" ]; then
        err "Cannot get pkts1"
        return 1
    fi

    if [ -z "$pkts2" ]; then
        err "Cannot get pkts2"
        return 1
    fi

    local total_pkts=$(($pkts1+$pkts2))
    debug "Received $total_pkts packets in SW"
    if [ $total_pkts -gt $num_of_pkts ]; then
        err "$total_pkts reached SW"
        return 1
    fi
}

function check_offload_contains() {
    local text=$1
    local num_flows=$2

    local flows=$(ovs-appctl dpctl/dump-flows -m type=offloaded | grep "$1" |wc -l)
    if [ $flows -ne $num_flows ]; then
        err "expected $num_flows flows with $1 message but got $flows"
        echo "flows:"
        ovs-appctl dpctl/dump-flows -m
    fi
}

function check_dpdk_offloads() {
    local IP=$1
    local filter='icmpv6\|arp\|drop\|ct_state(0x21/0x21)\|flow-dump\|actions:pf'

    if [[ $IP != *":"* ]]; then
        filter="ipv6\|${filter}"
    fi

    ovs-appctl dpctl/dump-flows -m | grep -v $filter | grep -- $IP'\|tnl_pop' &> /tmp/filtered.txt
    local x=$(cat /tmp/filtered.txt | wc -l)
    debug "Number of filtered rules: $x"

    cat /tmp/filtered.txt | grep 'offloaded:yes' &> /tmp/offloaded.txt
    local y=$(cat /tmp/offloaded.txt | wc -l)
    debug "Number of offloaded rules: $y"

    if [ $x -ne $y ]; then
        err "offloads failed"
        debug "Filtered rules:"
        cat /tmp/filtered.txt
        debug "Offloaded rules:"
        cat /tmp/offloaded.txt
        rm -rf /tmp/offloaded.txt /tmp/filtered.txt
        return 1
    elif [ $x -eq 0 ]; then
        err "offloads failed. no rules."
        rm -rf /tmp/offloaded.txt /tmp/filtered.txt
        return 1
    fi

    query_sw_packets
    rm -rf /tmp/offloaded.txt /tmp/filtered.txt
}

function del_openflow_rules() {
    local bridge=$1

    ovs-ofctl del-flows $bridge
    sleep 1
}

function check_offloaded_connections() {
    local num_of_connections=$1

    local x=$(ovs-appctl dpctl/offload-stats-show | grep 'Total' | grep 'CT bi-dir Connections:' | awk '{print $5}')
    if [ $x -lt $num_of_connections ]; then
        err "No offloaded connections created, expected $num_of_connections, got $x"
    else
        debug "Number of offloaded connections: $x"
    fi
}

function add_local_mirror() {
    local port=${1:-local-mirror}
    local rep_num=$2
    local bridge=$3

    ovs-vsctl add-port $bridge $port -- set interface $port type=dpdk options:dpdk-devargs=$PCI,representor=[${rep_num}] \
    -- --id=@p get port $port -- --id=@m create mirror name=m0 select-all=true output-port=@p \
    -- set bridge $bridge mirrors=@m
}

function add_remote_mirror() {
    local type=$1
    local bridge=$2
    local vni=$3
    local remote_addr=$4
    local local_addr=$5

    ip a add $local_addr/24 dev br-phy &> /dev/null
    ip l set br-phy up &> /dev/null
    ovs-vsctl add-port $bridge ${type}M -- set interface ${type}M type=$type options:key=$vni options:remote_ip=$remote_addr options:local_ip=$local_addr \
    -- --id=@p get port ${type}M -- --id=@m create mirror name=m0 select-all=true output-port=@p \
    -- set bridge $bridge mirrors=@m
}

function cleanup_mirrors() {
    local bridge=$1

    ovs-vsctl clear bridge $bridge mirrors &> /dev/null
}

function check_e2e_stats() {
    local expected_add_hw_messages=$1

    local x=$(ovs-appctl dpctl/offload-stats-show -m | grep 'Total' | grep 'HW add e2e flows:' | awk '{print $6}')
    debug "Number of offload messages: $x"

    if [ $x -lt $((expected_add_hw_messages)) ]; then
        err "offloads failed"
    fi

    debug "Sleeping for 15 seconds to age the flows"
    sleep 15
    # check deletion from DB
    local y=$(ovs-appctl dpctl/offload-stats-show -m | grep 'Total' | grep 'Merged e2e flows:' | awk '{print $5}')
    debug "Number of DB entries: $y"

    if [ $y -ge 2 ]; then
        err "deletion from DB failed"
    fi

    local z=$(ovs-appctl dpctl/offload-stats-show -m | grep 'Total' | grep 'HW del e2e flows:' | awk '{print $6}')
    debug "Number of delete HW messages: $z"

    if [ $z -lt $((expected_add_hw_messages)) ]; then
        err "offloads failed"
    fi
}

function enable_ct_ct_nat_offload {
    ovs-vsctl set open_vswitch . other_config:ct-action-on-nat-conns=true
}

function cleanup_ct_ct_nat_offload {
    ovs-vsctl remove open_vswitch . other_config ct-action-on-nat-conns
}
