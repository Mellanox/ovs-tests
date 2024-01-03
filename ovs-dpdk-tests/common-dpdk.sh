[ -z "$CLEAR_OVS_LOG" ] && CLEAR_OVS_LOG=1
[ -z "$ENABLE_OVS_DEBUG" ] && ENABLE_OVS_DEBUG=1

DPDK_DIR=$(cd "$(dirname ${BASH_SOURCE[0]})" && pwd)
. $DPDK_DIR/../common.sh
. $DPDK_DIR/common-tunnel.sh
. $DPDK_DIR/common-testing.sh

VDPA_DEV_NAME="eth2"
OFFLOAD_FILTER="offloaded:yes"
SLOW_PATH_TRAFFIC_PERCENTAGE=10

function is_dpdk() {
    [ "$DPDK" == 1 ] && return 0
    return 1
}

function is_doca() {
    [ "$DOCA" == 1 ] && return 0
    return 1
}

if is_doca; then
    DPDK_PORT_EXTRA_ARGS="dv_xmeta_en=4,dv_flow_en=2"
    OFFLOAD_FILTER="${OFFLOAD_FILTER}.*dp:doca"
elif is_dpdk; then
    DPDK_PORT_EXTRA_ARGS="dv_xmeta_en=1"
    OFFLOAD_FILTER="${OFFLOAD_FILTER}.*dp:dpdk"
fi


function set_ovs_dpdk_debug_logs() {
    local log="/var/log/openvswitch/ovs-vswitchd.log"
    if [ "$ENABLE_OVS_DEBUG" != "1" ]; then
        return
    fi
    if [ -f $log ]; then
        echo > $log
    fi
    if is_doca; then
        ovs_set_log_levels dpif_netdev:file:DBG netdev_offload_dpdk:file:DBG ovs_doca:DBG dpdk_offload_doca:DBG
    elif is_dpdk; then
        ovs_set_log_levels dpif_netdev:file:DBG netdev_offload_dpdk:file:DBG
    fi
}

function require_dpdk() {
    ! is_dpdk && fail "Not configured DPDK=1"
}

function get_port_from_pci() {
    local pci=${1-$PCI}
    local rep=$2
    local port="pf0"

    if [ "$pci" == "$PCI2" ] || [ "$pci" == "$BF_PCI2" ]; then
        port="pf1"
    fi

    port="$port"

    if [ -n "$rep" ]; then
        port+="vf$rep"
    fi

    echo "$port"
}

function __setup_common_dpdk() {
    if [ "$DOCA" == 1 ]; then
        DPDK=1
    fi

    IB_PF0_PORT0=`get_port_from_pci $PCI 0`
    IB_PF0_PORT1=`get_port_from_pci $PCI 1`
}

__setup_common_dpdk
require_dpdk
set_ovs_dpdk_debug_logs

function is_vdpa() {
    [ "$VDPA" == 1 ]
}

function config_vdpa_port() {
    local bridge=$1
    local pci=$2
    local i=$3

    local rep=`get_port_from_pci $pci $i`
    local vf_num="VF$((i+1))"
    local vfpci=$(get_vf_pci ${!vf_num})
    local vdpa_socket="/tmp/sock$(($i+1))"
    local vdpa_opts="options:vdpa-socket-path=$vdpa_socket options:vdpa-accelerator-devargs=$vfpci"
    local dpdk_opts="options:dpdk-devargs=$pci,representor=[$i],$DPDK_PORT_EXTRA_ARGS"

    if [ "$i" == "0" ]; then
        debug "Add ovs vdpa port $rep"
        ovs-vsctl add-port $bridge "$rep" -- set Interface "$rep" type=dpdkvdpa $vdpa_opts $dpdk_opts
    else
        debug "Add ovs vdpa port ${rep}_vdpa"
        ovs-vsctl add-port $bridge ${rep}_vdpa -- set Interface ${rep}_vdpa type=dpdkvdpa $vdpa_opts
        debug "Add ovs port $rep"
        ovs-vsctl add-port $bridge "$rep" -- set Interface "$rep" type=dpdk $dpdk_opts
    fi
}

function configure_dpdk_rep_ports() {
    local reps=$1
    local bridge=$2
    local pci=${3-$PCI}
    local i

    for (( i=0; i<$reps; i++ )); do
        if is_vdpa; then
            config_vdpa_port $bridge $pci $i
        else
            ovs_add_port VF $i $bridge $pci
        fi
    done
}

function ignore_expected_dpdk_err_msg() {
    # [MLNX OFED] Bug SW #2334320: [OVS-DPDK] Failed to init debugfs files appears in dmesg after configure the setup
    add_expected_error_msg ".*Failed to init debugfs files.*"
}

ignore_expected_dpdk_err_msg

function ovs_add_bridge() {
    local bridge=${1:-br-phy}
    exec_dbg ovs-vsctl --timeout=10 --may-exist add-br $bridge \
              -- set Bridge $bridge datapath_type=netdev fail-mode=standalone \
              -- br-set-external-id $bridge bridge-id $bridge || err "Failed to add bridge $bridge"
}

function ovs_add_port() {
    local type=$1
    local num=${2:-"1"}
    local bridge=${3:-br-phy}
    local pci=${4:-`get_pf_pci`}
    local mtu=$5
    local port=`get_port_from_pci $pci`

    if [ -z "$pci" ]; then
        err "ovs_add_port: pci is empty"
        return
    fi

    if ([ "$type" == "ECPF" ] && ! (is_bf || is_bf_host)); then
        return
    fi

    local dpdk_opts="options:dpdk-devargs=$pci,$DPDK_PORT_EXTRA_ARGS"
    local port_type

    if [ "$type" == "ECPF" ]; then
        port+="hpf"
        dpdk_opts+=",representor=[65535]"
        port_type="dpdk"
    elif [ "$type" == "PF" ]; then
        port_type="dpdk"
    elif [ "$type" == "VF" ]; then
        port+="vf$num"
        dpdk_opts+=",representor=[$num]"
        port_type="dpdk"
    elif [ "$type" == "SF" ]; then
        port+="sf$num"
        dpdk_opts+=",representor=sf[$num]"
        port_type="dpdk"
    else
        port=$num
        port_type=$type
        dpdk_opts=""
    fi

    if [ -n "$mtu" ]; then
        dpdk_opts+=" mtu_request=$mtu"
    fi

    __ovs_add_port $bridge $port $port_type "$dpdk_opts"
}

function __ovs_add_port() {
    local bridge=$1
    local port=$2
    local port_type=$3
    local opts=$4

    debug "Add ovs $port_type port $port"
    exec_dbg ovs-vsctl --timeout=10 add-port $bridge $port -- set Interface $port type=$port_type $opts || err "Failed to add port $bridge $port"
}

function ovs_del_port() {
    local type=$1
    local num=${2:-"1"}
    local bridge=${3:-br-phy}
    local pci=${4:-`get_pf_pci`}
    local port=`get_port_from_pci $pci`

    if [ "$type" == "ECPF" ]; then
        port+="hpf"
    elif [ "$type" == "PF" ]; then
        port=$port
    elif [ "$type" == "VF" ]; then
        port+="vf$num"
    elif [ "$type" == "SF" ]; then
        port+="sf$num"
    else
        port=$num
    fi

    debug "Del ovs $type port $port"
    ovs-vsctl del-port $bridge $port || err "Failed to del port $bridge $port"
}

function config_remote_bridge_tunnel() {
    local vni=$1
    local remote_ip=$2
    local tnl_type=${3:-vxlan}
    local reps=${4:-1}
    local bridge=${5:-"br-int"}
    local pci=${6:-`get_pf_pci`}
    local port="${tnl_type}_$bridge"
    local opts="options:key=$vni options:remote_ip=$remote_ip"

    debug "Configuring remote bridge tunnel $tnl_type key $vni remote_ip $remote_ip with $reps reps"
    ovs_add_bridge $bridge
    ovs-vsctl add-port $bridge $port -- set interface $port type=$tnl_type $opts

    configure_dpdk_rep_ports $reps $bridge $pci
}

function config_simple_bridge_with_rep() {
    local reps=$1
    local should_add_pf=${2:-"true"}
    local bridge=${3:-"br-phy"}
    local nic=${4:-"$NIC"}
    local pf_mtu=$5
    local pci=$(get_pf_pci)

    if [ $nic == $NIC2 ]; then
        pci=$(get_pf_pci2)
    fi

    debug "Configuring bridge $bridge with $reps reps"
    ovs_add_bridge $bridge

    if [ "$should_add_pf" == "true" ]; then
        ovs_add_port "PF" 0 $bridge $pci $pf_mtu
    fi
    configure_dpdk_rep_ports $reps $bridge $pci
}

function start_vdpa_vm1() {
    local wait_vm=${1:-"yes"}
    start_vdpa_vm $NESTED_VM_NAME1 $NESTED_VM_IP1
    [ "$wait_vm" == "yes" ] && wait_vdpa_vm $NESTED_VM_NAME1 $NESTED_VM_IP1
}

function start_vdpa_vm2() {
    local wait_vm=${1:-"yes"}
    start_vdpa_vm $NESTED_VM_NAME2 $NESTED_VM_IP2
    [ "$wait_vm" == "yes" ] && wait_vdpa_vm $NESTED_VM_NAME2 $NESTED_VM_IP2
}

function start_vdpa_vms() {
    start_vdpa_vm1 no_wait
    start_vdpa_vm2 no_wait
    wait_vdpa_vm $NESTED_VM_NAME1 $NESTED_VM_IP1
    wait_vdpa_vm $NESTED_VM_NAME2 $NESTED_VM_IP2
}

function start_vdpa_vm() {
    local vm_name=${1:-$NESTED_VM_NAME1}
    local vm_ip=${2:-$NESTED_VM_IP1}

    if ! is_vdpa; then
        return
    fi

    local status=$(virsh list --all | grep $vm_name | awk '{ print $3 }')

    if [ "${status}" == "running" ]; then
        success "VM $vm_name already started"
        return
    fi

    debug "Starting VM $vm_name"
    timeout --foreground 20 virsh start $vm_name &>/dev/null
    if [ $? -ne 0 ]; then
        fail "Could not start VM"
    fi

    success "VM $vm_name started. wait for it to be ready."
    # should call wait_vdpa_vm() before using the vm.
}

function wait_vdpa_vm() {
    local vm_name=${1:-$NESTED_VM_NAME1}
    local vm_ip=${2:-$NESTED_VM_IP1}

    if ! is_vdpa; then
        return
    fi

    local status
    local i

    for i in {0..60}; do
        status=$(virsh list --all | grep "$vm_name" | awk '{ print $3 }')
        if [ "${status}" == "running" ]; then
            break
        fi
        sleep 1
    done

    if [ "${status}" != "running" ]; then
        fail "VM is not running"
    fi

    local vm_started="false"

    for i in {0..60}; do
        if ping -c1 -w1 $vm_ip &>/dev/null; then
            vm_started="true"
            break
        fi
    done

    if [ "${vm_started}" == "false" ]; then
        fail "Timeout waiting for VM to start"
    fi

    sleep 2
    __on_remote $vm_ip true || fail "VM is not ready"
    success "VM $vm_name is ready"
}

function config_local_tunnel_ip() {
    local ip_addr=$1
    local dev=$2
    local subnet=${3:-24}

    bf_wrap "ip addr add $ip_addr/$subnet dev $dev
             ip link set $dev up"
}

function config_static_ipv6_neigh_ns() {
    local ns=$1
    local ns2=$2
    local src_dev=$3
    local dst_dev=$4
    local ip_addr=$5
    local dst_execution1="ip netns exec $ns"
    local dst_execution2="ip netns exec $ns2"

    if is_vdpa; then
        dst_execution1="on_vm1"
        dst_execution2="on_vm2"
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

    if is_vdpa; then
        dst_execution1="on_vm1"
        dst_execution2="on_vm2"
        dev=$VDPA_DEV_NAME
    fi

    local mac=$(${dst_execution1} cat /sys/class/net/$dev/address)
    local cmd1="${dst_execution2} arp -s $ip_addr $mac"
    eval $cmd1
}

function config_ns() {
    local ns=$1
    local dev=$2
    local ip_addr=$3
    local ipv6_addr=${4-"2001:db8:0:f101::1"}
    local on_vm="ip netns exec $ns"

    if is_vdpa; then
        if [ "$ns" == "ns0" ]; then
	    on_vm="on_vm1"
	else
            on_vm="on_vm2"
        fi

        debug "Set $VDPA_DEV_NAME ip $ip_addr on vm $on_vm"
	dev=$VDPA_DEV_NAME
    else
        debug "Attach $dev to namespace $ns"
	if ! ip netns ls | grep -w $ns >/dev/null; then
	    ip netns add $ns
	fi
        ip link set $dev netns $ns || err "Failed to attach device to ns"
    fi

    for ip in $ip_addr; do
        $on_vm ip address add $ip/24 dev $dev
    done
    $on_vm ip link set dev $dev up
    $on_vm ip -6 address add $ipv6_addr/64 dev $dev
}

__ovs_e2e_cache_set=0
function set_e2e_cache_enable() {
    local enabled=${1:-true}
    __ovs_e2e_cache_set=1
    ovs-vsctl --no-wait set Open_vSwitch . other_config:e2e-enable=${enabled}
}

function cleanup_e2e_cache() {
    [ "$__ovs_e2e_cache_set" == 1 ] || return
    ovs-vsctl --no-wait remove Open_vSwitch . other_config e2e-enable
}

function clear_pmd_stats() {
    ovs-appctl dpif-netdev/pmd-stats-clear
}

function get_total_packets_passed_in_sw() {
    local pkts1=$(ovs-appctl dpif-netdev/pmd-stats-show | grep 'packets received:' | sed -n '1p' | awk '{print $3}')
    local pkts2=$(ovs-appctl dpif-netdev/pmd-stats-show | grep 'packets received:' | sed -n '2p' | awk '{print $3}')

    if [ -z "$pkts1" ]; then
        err_stderr "Cannot get pkts1"
        return
    fi

    if [ -z "$pkts2" ]; then
        err_stderr "Cannot get pkts2"
        return
    fi

    echo $(($pkts1+$pkts2))
}

function __verify_bridge_pkts() {
    local bridge_pkts=$1
    # We don't expect a rule with so much traffic but we noticed ovs reporting
    # invalid stats. catch it here.
    ((bridge_pkts+=0))
    if [ $bridge_pkts -lt 0 ] || [ $bridge_pkts -gt 100000000000000 ]; then
        err_stderr "Invalid packet count $bridge_pkts ?"
        return 1
    fi
    return 0
}

function get_total_packets_passed() {
    local pkts=0
    local bridge_pkts

    for br in `ovs-vsctl list-br`; do
        bridge_pkts=$(ovs-ofctl dump-flows $br | grep "table=0" | grep -o "n_packets=[0-9.]*" | cut -d= -f2 | awk '{ SUM += $1} END { print SUM }')
        __verify_bridge_pkts $bridge_pkts || return
        ((pkts += bridge_pkts))
    done

    if [ $pkts -eq 0 ]; then
        err_stderr "Cannot get pkts"
        return
    fi

    echo $pkts
}

function set_slow_path_percentage() {
    local percentage=$1
    local reason=$2

    if [ -z "$percentage" ]; then
        err "Cannot set slow path percentage, missing parameter"
        return 1
    fi

    if [ -z "$reason" ]; then
        err "Cannot change slow path percentage without providing a reason, missing parameter"
        return 1
    fi

    SLOW_PATH_TRAFFIC_PERCENTAGE=$1
    debug "Slow path percentage set to $percentage, because: \"$reason\""
}

function ovs_dump_flows_all_bridges() {
    local br

    for br in `ovs-vsctl list-br`; do
        echo $br
        ovs-ofctl dump-flows --color $br
    done
}

function query_sw_packets_in_sent_packets_percentage() {
    local valid_percentage_passed_in_sw=$SLOW_PATH_TRAFFIC_PERCENTAGE

    local total_packets_passed_in_sw=$(get_total_packets_passed_in_sw)
    local all_packets_passed=$(get_total_packets_passed)
    local ret=0

    if [ -z "$total_packets_passed_in_sw" ]; then
        err "Cannot get total_packets_passed_in_sw"
        ret=1
    fi

    if [ -z "$all_packets_passed" ]; then
        err "Cannot get all_packets_passed"
        ret=1
    fi

    if [ "$ret" == 1 ]; then
        ovs_dump_flows_all_bridges
        return 1
    fi

    title "Checking that $total_packets_passed_in_sw is no more than $valid_percentage_passed_in_sw% of $all_packets_passed"
    local a=$(($valid_percentage_passed_in_sw*$all_packets_passed/100))

    if [ $a -lt $total_packets_passed_in_sw ]; then
        err "$total_packets_passed_in_sw packets passed in SW, it is more than $valid_percentage_passed_in_sw% of $all_packets_passed"
        return 1
    elif [ $a -ge $total_packets_passed_in_sw ]; then
        success
        return 0
    fi

    err "Failed to parse numbers"
    return 1
}

function query_sw_packets() {
    local expected_num_of_pkts=100000

    if [[ "$short_device_name" == "cx5"* ]]; then
        expected_num_of_pkts=350000
    fi

    debug "Expecting $expected_num_of_pkts to reach SW"

    local total_packets_passed_in_sw=$(get_total_packets_passed_in_sw)

    if [ -z "$total_packets_passed_in_sw" ]; then
        err "Cannot get total_packets_passed_in_sw"
        return 1
    fi

    debug "Received $total_packets_passed_in_sw packets in SW"

    if [ $total_packets_passed_in_sw -gt $expected_num_of_pkts ]; then
        query_sw_packets_in_sent_packets_percentage
        return $?
    fi
    return 0
}

function check_offload_contains() {
    local text=$1
    local num_flows=$2

    title "Check offloaded rules with $text"

    local flows=$(ovs-appctl dpctl/dump-flows -m type=offloaded | grep -E "$text" | wc -l)
    if [ $flows -ne $num_flows ]; then
        err "expected $num_flows flows with $text message but got $flows"
        echo "flows:"
        ovs-appctl dpctl/dump-flows -m
    fi
}

function check_dpdk_offloads() {
    local IP=$1
    local filter='arp\|drop\|ct_state(0x21/0x21)\|flow-dump\|nd(\|33:33:00:00'
    local regex_filter='icmp.*ct\(.*'
    local ovs_type="DPDK"

    if is_doca; then
        ovs_type="DOCA"
    else
        local pci=$(get_pf_pci)
        local pci2=$(get_pf_pci2)
        local pf0=`get_port_from_pci $pci`
        local pf1=`get_port_from_pci $pci2`
        filter="actions:$pf1\b\|actions:$pf0\b\|${filter}"
    fi

    title "Check $ovs_type offloads"

    if ! ovs-appctl dpctl/dump-flows -m > /tmp/dump.txt ; then
        err "ovs-appctl failed"
        return 1
    fi

    grep -v $filter /tmp/dump.txt | grep -v -E $regex_filter | grep -i -- "$IP\|$LOCAL_TUN_IP\|tnl_pop" > /tmp/filtered.txt

    local x=$(cat /tmp/filtered.txt | wc -l)
    debug "Number of filtered rules: $x"

    cat /tmp/filtered.txt | grep -E "$OFFLOAD_FILTER" > /tmp/offloaded.txt
    local y=$(cat /tmp/offloaded.txt | wc -l)
    debug "Number of offloaded rules: $y"

    if [ $x -ne $y ]; then
        err "Number of filtered rules expected to be same as offloaded rules."
        debug "Unexpected rules:"
        cat /tmp/filtered.txt | grep -v -E "$OFFLOAD_FILTER"
    elif [ $x -eq 0 ]; then
        err "No offloaded rules."
    else
        query_sw_packets
    fi

    rm -rf /tmp/offloaded.txt /tmp/filtered.txt
}

function del_openflow_rules() {
    local bridge=$1

    ovs-ofctl del-flows $bridge
    sleep 1
}

function check_offloaded_connections() {
    local expected_connections=$1
    local current_connections
    local result=0

    title "Check offloaded CT connections"

    for (( i=0; i<3; i++ )); do
        current_connections=$(ovs-appctl dpctl/offload-stats-show | grep -i -E "Total.*CT bi-dir Connections:" | awk '{print $5}')
        if [ -z "$current_connections" ]; then
            err "Failed to get stats"
            break
        elif [ $current_connections -lt $expected_connections ]; then
            debug "Number of offloaded connections $current_connections is lower than expected $expected_connections - recheck"
            sleep 0.7
        elif [ $current_connections -ge $expected_connections ]; then
            result=1
            debug "Number of offloaded connections $current_connections is at least as expected $expected_connections"
            break
        else
            err "Failed to get stats"
            break
        fi
    done

    if [ "$result" == "0" ] ; then
        err "Number of offloaded connections $current_connections is lower than expected $expected_connections"
    fi
}

function __check_ct_est_packet_count_br() {
    local br=$1
    local ct_est_pkts=`ovs-ofctl dump-flows $br | grep -w "+est" | grep -o "n_packets=[0-9]\+" | cut -d= -f2`

    # no CT est rule.
    [ -z "$ct_est_pkts" ] && return

    title "Check CT est packet count on bridge $br"

    local pkts
    local i=1

    for pkts in $ct_est_pkts; do
        if [ $pkts -gt 5 ]; then
            success "Rule #$i: CT est packet count: $pkts"
            let i+=1
            continue
        fi

        err "Incorrect ct est packet count: $pkts"
        ovs-ofctl dump-flows $br | grep -w "+est"
    done
}

function check_ct_est_packet_count() {
    local br

    for br in `ovs-vsctl list-br`; do
        __check_ct_est_packet_count_br $br
    done
}

function check_offloaded_connections_marks() {
    local expected=$1
    local proto=$2
    local actual
    local result

    title "Check offloaded connections"

    for (( i=0; i<3; i++ )); do
        actual=$(ovs-appctl dpctl/dump-flows -m --names | grep -w $proto | grep "offloaded:yes" | wc -l)
        if [ "$actual" != "$expected" ]; then
            result="0"
            debug "Unexpected number of connections marked as offloaded, actual $actual vs expected $expected - recheck"
            sleep 0.7
        else
            result="1"
            debug "Number of connections marked as offloaded: $actual is as expected $expected"
            break
        fi
    done

    if [ "$result" == "0" ] ; then
        err "Unexpected number of connections marked as offloaded, actual $actual vs expected $expected"
    fi
}

function add_local_mirror() {
    local port=${1:-local-mirror}
    local rep_num=$2
    local bridge=$3
    local pci=$(get_pf_pci)

    local dpdk_opts="options:dpdk-devargs=$pci,representor=[$rep_num],$DPDK_PORT_EXTRA_ARGS"

    local mirror_opts="-- --id=@p get port $port -- --id=@m create mirror name=m0 select-all=true output-port=@p \
                       -- set bridge $bridge mirrors=@m"

    ovs-vsctl add-port $bridge $port -- set interface $port type=dpdk $dpdk_opts $mirror_opts
}

function add_remote_mirror() {
    local type=$1
    local bridge=$2
    local vni=$3
    local remote_addr=$4
    local local_addr=$5
    local port="${type}M"

    local mirror_opts="-- --id=@p get port $port -- --id=@m create mirror name=m0 select-all=true output-port=@p \
                       -- set bridge $bridge mirrors=@m"
    local tun_opts="options:key=$vni options:remote_ip=$remote_addr options:local_ip=$local_addr"

    ip a add $local_addr/24 dev br-phy
    ip l set br-phy up

    ovs-vsctl add-port $bridge $port -- set interface $port type=$type $tun_opts $mirror_opts
}

function cleanup_mirrors() {
    local bridge=$1

    ovs-vsctl clear bridge $bridge mirrors &> /dev/null
}

function check_e2e_stats() {
    local expected_add_hw_messages=$1
    local appctl_cmd=$2

    title "Check e2e stats"

    local x=$(ovs-appctl dpctl/offload-stats-show -m | grep 'Total' | grep 'HW add e2e flows:' | awk '{print $6}')
    debug "Number of offload messages: $x"

    if [ $x -lt $((expected_add_hw_messages)) ]; then
        err "offloads failed"
    fi

    if [ -z "$appctl_cmd" ]; then
        debug "Sleeping for 15 seconds to age the flows"
        sleep 15
    else
        exec_dbg "ovs-appctl $appctl_cmd" || err "ovs-appctl $appctl_cmd failed"
        sleep 1
    fi

    # check deletion from DB
    local y=$(ovs-appctl dpctl/offload-stats-show -m | grep 'Total' | grep 'Merged e2e flows:' | awk '{print $5}')
    debug "Number of DB entries: $y"

    if [ $y -ge 2 ]; then
        ovs-appctl dpctl/offload-stats-show -m
        err "deletion from DB failed"
    fi

    local z=$(ovs-appctl dpctl/offload-stats-show -m | grep 'Total' | grep 'HW del e2e flows:' | awk '{print $6}')
    debug "Number of delete HW messages: $z"

    if [ $z -lt $((expected_add_hw_messages)) ]; then
        ovs-appctl dpctl/offload-stats-show -m
        err "offloads failed"
    fi
}

__ovs_ct_ct_nat_offload_set=0
function enable_ct_ct_nat_offload {
    __ct_ct_nat_offload_set=1
    ovs-vsctl set open_vswitch . other_config:ct-action-on-nat-conns=true
}

function cleanup_ct_ct_nat_offload {
    [ "$__ct_ct_nat_offload_set" == 1 ] || return
    ovs-vsctl remove open_vswitch . other_config ct-action-on-nat-conns
}

function check_counters {
    check_tcp_sequence
}

function check_tcp_sequence {
    local cmd="ovs-appctl coverage/read-counter conntrack_tcp_seq_chk_failed"
    local val=$(eval $cmd)

    title "Check tcp sequence"

    if [ $val -ne 0 ]; then
        err "$cmd value $val is greater than zero"
    fi
}

function set_flex_parser() {
    local val=$1

    # ovs-dpdk takes module refcount. stop it first.
    stop_openvswitch
    fw_config "FLEX_PARSER_PROFILE_ENABLE=$val" || fail "could not set flex parser profile"
    fw_reset
}

function get_grace_period() {
    is_bf_host && warn "skip get_grace_period on bf" && return

    local pci=`get_pf_pci`

    grace_period=`devlink health show pci/$pci reporter fw_fatal | grep -Eo "grace_period [0-9]+" | awk {'print $2'}`

    if [ -z $grace_period ]; then
        fail "Failed to get grace period"
    fi
}

function set_grace_period() {
    is_bf_host && warn "skip set_grace_period on bf" && return

    local value=$1
    local pci=`get_pf_pci`
    local pci2=`get_pf_pci2`

    devlink health set pci/$pci reporter fw_fatal grace_period $value || err "Failed to change grace period to $value for $pci"
    devlink health set pci/$pci2 reporter fw_fatal grace_period $value || err "Failed to change grace period to $value for $pci2"
}

function config_devices() {
    config_sriov 2
    config_sriov 2 $NIC2
    enable_switchdev
    enable_switchdev $NIC2
    bind_vfs
    bind_vfs $NIC2
}

function ovs_enable_hw_offload_ct_ipv6 {
    ovs_conf_set hw-offload-ct-ipv6-enabled true
}

function ovs_cleanup_hw_offload_ct_ipv6 {
    ovs_conf_remove hw-offload-ct-ipv6-enabled
}

# $1: <uint> size to configure
function ovs_set_hw_offload_ct_size {
    local size=$1
    [ "$size" ] || err "CT-Size parameter required but not provided."
    ovs_conf_set hw-offload-ct-size $size
}

function ovs_cleanup_hw_offload_ct_size {
    ovs_conf_remove hw-offload-ct-size
}

function ovs_set_ct_zone_timeout() {
    local zone=$1
    local tp=$2
    local timeout=$3

    ovs-vsctl -- --id=@m create Datapath datapath_version=0 -- set open_vswitch . datapaths:netdev=@m
    if [ "$tp" == "udp" ]; then
        ovs-vsctl add-zone-tp netdev zone=$zone udp_first=$timeout udp_single=$timeout udp_multiple=$timeout
    else
        ovs-vsctl add-zone-tp netdev zone=$zone tcp_syn_sent=$timeout tcp_syn_recv=$timeout tcp_established=$timeout tcp_fin_wait=$timeout tcp_time_wait=$timeout tcp_close=$timeout
    fi
}

function ovs_clear_datapaths() {
    # call to clear functions adding custom netdev datapath like ovs_set_ct_zone_timeout().
    ovs-vsctl  clear open_vswitch . datapaths
}

function check_resize_counter() {
    local counter=`ovs-appctl coverage/read-counter doca_pipe_resize`

    if [ $counter -lt 1 ]; then
        fail "No resize found"
    fi
    success "got $counter resize(s)"
}

if [[ "$TESTNAME" == "common-dpdk.sh" ]]; then
    __common_eval $@
fi
