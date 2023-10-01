LOCAL_IP=1.1.1.7
REMOTE_IP=1.1.1.8
LOCAL_IP2=2.2.2.7
REMOTE_IP2=2.2.2.8

p_server=/tmp/perf_server
p_client=/tmp/perf_client
p_scapy=/tmp/tcpdump
num_connections=5
iperf_cmd=iperf3

function set_iperf2() {
    iperf_cmd=iperf
}

function ovs_ofctl_dump_flows() {
    debug "OVS flow rules:"
    ovs-ofctl dump-flows $bridge --color
}

function ovs_add_ct_after_nat_rules() {
    local bridge=$1
    local ip=$2
    local dummy_ip=$3
    local rep=${4:-"$IB_PF0_PORT0"}
    local rep2=${5:-"$IB_PF0_PORT1"}

    ovs-ofctl del-flows $bridge
    ovs-ofctl add-flow $bridge "table=0,priority=1,actions=drop"
    ovs-ofctl add-flow $bridge "table=0,priority=10,arp,actions=NORMAL"
    ovs-ofctl add-flow $bridge "table=0,priority=10,icmp,actions=NORMAL"
    ovs-ofctl add-flow $bridge "table=0,priority=20,in_port=$rep2,ip,actions=ct(nat),$rep"
    ovs-ofctl add-flow $bridge "table=0,priority=30,in_port=$rep,ip,nw_dst=$dummy_ip,actions=ct(commit,nat(dst=$ip:5201),table=1)"
    ovs-ofctl add-flow $bridge "table=1,ip,actions=ct(commit,table=2)"
    ovs-ofctl add-flow $bridge "table=2,in_port=$rep,ip,actions=$rep2"
    ovs_ofctl_dump_flows
}

function ovs_add_ipv6_mod_hdr_rules() {
    local my_ipv6=$1
    local peer_ipv6=$2
    local dummy_peer_ipv6=$3
    local bridge=${4:-"br-phy"}
    local rep0=${5:-"$IB_PF0_PORT0"}
    local rep1=${6:-"$IB_PF0_PORT1"}

    debug "Adding ipv6_mod_hdr rules"
    ovs-ofctl del-flows $bridge
    ovs-ofctl del-flows -OOpenFlow15 $bridge
    ovs-ofctl add-flow -OOpenFlow15 $bridge in_port=$rep0,ipv6,ipv6_dst=${dummy_peer_ipv6},ipv6_src=${my_ipv6},actions=set_field:${peer_ipv6}-\>ipv6_dst,set_field:${my_ipv6}-\>ipv6_src,$rep1
    ovs-ofctl add-flow -OOpenFlow15 $bridge in_port=$rep1,ipv6,ipv6_dst=${my_ipv6},ipv6_src=${peer_ipv6},actions=set_field:${my_ipv6}-\>ipv6_dst,set_field:${dummy_peer_ipv6}-\>ipv6_src,$rep0
    ovs_ofctl_dump_flows
}

function ovs_add_ct_dnat_rules() {
    local rx_port=$1
    local tx_port=$2
    local nat_ip=$3
    local proto=$4
    local nat_port=${5:-""}
    local bridge=${6:-br-phy}

    debug "Adding ct-nat rules"
    ovs-ofctl del-flows $bridge
    ovs-ofctl add-flow $bridge "table=0,arp,actions=NORMAL"
    ovs-ofctl add-flow $bridge "table=0,in_port=${rx_port},${proto},ct_state=-trk, actions=ct(zone=2, table=1, commit, nat(dst=$nat_ip${nat_port}))"
    ovs-ofctl add-flow $bridge "table=1,in_port=${rx_port},${proto},ct_state=+trk+new, actions=ct(zone=2, commit),${tx_port}"
    ovs-ofctl add-flow $bridge "table=1,in_port=${rx_port},${proto},ct_state=+trk+est, actions=${tx_port}"
    ovs-ofctl add-flow $bridge "table=0,in_port=${tx_port},${proto},ct_state=-trk, actions=ct(zone=2, table=1, nat)"
    ovs-ofctl add-flow $bridge "table=1,in_port=${tx_port},${proto},ct_state=+trk+new, actions=ct(zone=2, commit),${rx_port}"
    ovs-ofctl add-flow $bridge "table=1,in_port=${tx_port},${proto},ct_state=+trk+est, actions=${rx_port}"
    ovs_ofctl_dump_flows
}

function ovs_add_ct_nat_nop_rules() {
    local bridge=${1:-"br-int"}

    debug "Adding ct_nat_nop rules"
    ovs-ofctl del-flows $bridge
    ovs-ofctl add-flow $bridge "arp,actions=normal"
    ovs-ofctl add-flow $bridge "table=0, ip,ct_state=-trk, actions=ct(table=1,nat)"
    ovs-ofctl add-flow $bridge "table=1, ip,ct_state=+trk+new, actions=ct(commit),normal"
    ovs-ofctl add-flow $bridge "table=1, ip,ct_state=+trk+est, actions=normal"
    ovs_ofctl_dump_flows
}

function ovs_add_ct_rules() {
    local bridge=${1:-"br-int"}
    local proto=${2:-"ip"}

    debug "Adding ct rules"
    ovs-ofctl del-flows $bridge
    ovs-ofctl add-flow $bridge "arp,actions=NORMAL"
    ovs-ofctl add-flow $bridge "icmp,actions=NORMAL"
    ovs-ofctl add-flow $bridge "icmp6,actions=NORMAL"
    ovs-ofctl add-flow $bridge "table=0,$proto,ct_state=-trk,actions=ct(zone=5, table=1)"
    ovs-ofctl add-flow $bridge "table=1,$proto,ct_state=+trk+new,actions=ct(zone=5, commit),NORMAL"
    ovs-ofctl add-flow $bridge "table=1,$proto,ct_state=+trk+est,ct_zone=5,actions=normal"
    ovs_ofctl_dump_flows
}

function ovs_add_ct_rules_dec_ttl() {
    local bridge=${1:-"br-int"}

    debug "Adding ct_dec_ttl rules"
    ovs-ofctl del-flows $bridge
    ovs-ofctl add-flow $bridge "arp,actions=NORMAL"
    ovs-ofctl add-flow $bridge "icmp,actions=NORMAL"
    ovs-ofctl add-flow $bridge "icmp6,actions=NORMAL"
    ovs-ofctl add-flow $bridge "table=0,ip,ct_state=-trk,actions=ct(zone=5, table=1)"
    ovs-ofctl add-flow $bridge "table=1,ip,ct_state=+trk+new,actions=ct(zone=5, commit),dec_ttl,NORMAL"
    ovs-ofctl add-flow $bridge "table=1,ip,ct_state=+trk+est,ct_zone=5,actions=dec_ttl,normal"
    ovs_ofctl_dump_flows
}

function ovs_add_meter() {
    local bridge=${1:-"br-phy"}
    local meter_id=${2:-0}
    local meter_type=${3:-"pktps"}
    local rate=${4:-1}
    local burst_size=$5
    local burst=""

    if [ -n "$burst_size" ]; then
        burst=",burst"
        burst_size=",burst_size=$burst_size"
    fi

    exec_dbg "ovs-ofctl -O openflow13 add-meter $bridge meter=${meter_id},${meter_type}${burst},band=type=drop,rate=${rate}${burst_size}"
}

function ovs_del_meter() {
    local bridge=${1:-"br-phy"}
    local meter_id=${2:-1}

    exec_dbg "ovs-ofctl -O openflow13 del-meter $bridge meter=${meter_id}"
    sleep 2
}

function ovs_wait_until_ipv6_done() {
    local remote_ip=${1:-$REMOTE_IP}
    local namespace=${2:-ns0}
    local dst_execution="ip netns exec $namespace"

    if [ "${VDPA}" == "1" ]; then
        dst_execution="on_vm1"
    fi

    local cmd="${dst_execution} ping -c1 -w 1 $remote_ip"
    if [[ $remote_ip = *":"* ]]; then
       cmd+=" -6"
    fi
    for i in {0..15}; do
        eval $cmd &> /dev/null
        if [ $? -ne 0 ]; then
            debug "sleeping for 1 second until IPv6 stack is set"
            sleep 1
        else
            return 0
        fi
    done
    fail "IPv6 solicitation failed"
}

function ovs_add_simple_meter_rule() {
    local bridge=${1:-"br-phy"}
    local meter_id=${2:-1}

    exec_dbg "ovs-ofctl -O openflow13 add-flow $bridge "priority=100,table=0,actions=meter:${meter_id},normal""
}

function ovs_add_bidir_meter_rules() {
    local bridge=${1:-"br-phy"}
    local meter_id1=${2:-1}
    local meter_id2=${3:-2}
    local in_port1=${4:-"$IB_PF0_PORT0"}
    local in_port2=${5:-"$IB_PF0_PORT1"}

    ovs-ofctl del-flows $bridge
    exec_dbg "ovs-ofctl -O openflow13 add-flow br-phy "table=0,in_port=${in_port1},actions=meter:${meter_id1},${in_port2}""
    exec_dbg "ovs-ofctl -O openflow13 add-flow br-phy "table=0,in_port=${in_port2},actions=meter:${meter_id2},${in_port1}""
}

function send_metered_ping() {
    local namespace=${1:-"ns0"}
    local count=${2:-100}
    local wait=${3:-5}
    local ip_addr=${4:-"1.1.1.8"}
    local interval=${5:-0.01}
    local expected_received=${6:-10}
    local p_ping="/tmp/ping_out"

    rm -rf $p_ping
    exec_dbg "ip netns exec $namespace ping -c $count -w $wait -i $interval $ip_addr > $p_ping"
    local pkts=$(grep 'received' $p_ping | awk '{ print $4 }')

    if [ $pkts -gt $expected_received ]; then
        err "Expected at most $expected_received packets but got $pkts packets"
        cat $p_ping
        return 1
    elif [ $pkts -le $expected_received ]; then
        success "Got $pkts packets"
    else
        err "Failed parsing number of received packets."
    fi
    rm -rf $p_ping
}

function ovs_check_tcpdump() {
    local expected=${1:-1}

    killall tcpdump
    sleep 1
    local pkts=$(tcpdump -nner $p_scapy udp | wc -l)
    if [ $pkts -gt $expected ]; then
        err "expected $expected to pass meter but got $pkts"
        tcpdump -nner $p_scapy
        return 1
    elif [ $pkts -le $expected ]; then
        success "expected at most $expected packets to pass and $pkts passed"
    else
        err "Failed ovs_check_tcpdump."
    fi
    rm -rf $p_scapy
}

function ovs_send_scapy_packets() {
    local dev1=$1
    local dev2=$2
    local src_ip=$3
    local dst_ip=$4
    local t=$5
    local pkt_count=$6
    local src_ns=$7
    local dst_ns=$8
    local pktgen="$DPDK_DIR/../scapy-traffic-tester.py"

    rm -rf $p_scapy
    local tcpdump_cmd="tcpdump -qnnei $dev2 -Q in -w $p_scapy &"
    local scapy_dst_cmd="timeout $((t+5)) $pktgen -l -i $dev2 --src-ip $src_ip --time $(($t+2)) &"
    local scapy_src_cmd="timeout $((t+5)) $pktgen -i $dev1 --src-ip $src_ip --dst-ip $dst_ip --time $t --pkt-count $pkt_count --inter 0.01 &"

    if [ -n "$src_ns" ]; then
        exec_dbg "ip netns exec $dst_ns $tcpdump_cmd"
        exec_dbg "ip netns exec $dst_ns $scapy_dst_cmd"
        exec_dbg "ip netns exec $src_ns $scapy_src_cmd"
    else
        exec_dbg "$tcpdump_cmd"
        exec_dbg "$scapy_dst_cmd"
        exec_dbg "$scapy_src_cmd"
    fi
    sleep 3
}

function verify_ping() {
    local remote_ip=${1:-$REMOTE_IP}
    local namespace=${2:-ns0}
    local size=${3:-56}
    local packet_num=${4:-10}
    local dst_execution="ip netns exec $namespace"

    if [ "${VDPA}" == "1" ]; then
        dst_execution="on_vm1"
        if [ "${namespace}" != "ns0" ]; then
            dst_execution="on_vm2"
        fi
    fi

    cmd="${dst_execution} ping -q -c $packet_num -w 2 -i 0.01 $remote_ip -s $size"

    if [[ $remote_ip = *":"* ]]; then
       cmd+=" -6"
    fi

    exec_dbg "$cmd"

    if [ $? -ne 0 ]; then
        err "ping failed"
        return 1
    fi
}

function verify_iperf_running() {
    local remote=${1:-"local"}
    proc_cmd="pidof -s $iperf_cmd"

    if [ "$remote" == "remote" ]; then
       proc_cmd="on_remote $proc_cmd"
    elif [ "${VDPA}" == "1" ]; then
       proc_cmd="on_vm1 $proc_cmd"
    fi

    title "Look for iperf pid"
    if ! $proc_cmd ; then
       err "No iperf process on $remote"
       stop_traffic
       return 1
    fi
}

function generate_traffic() {
    local remote=$1
    local my_ip=$2
    local namespace=$3
    local validate=${4:-true}

    initiate_traffic $remote $my_ip $namespace
    if [ "$validate" == "true" ]; then
        validate_offload $my_ip
    else
        wait_traffic
    fi
    validate_actual_traffic
    stop_traffic
}

function initiate_traffic() {
    local remote=$1
    local my_ip=$2
    local namespace=$3

    local server_dst_execution="ip netns exec ns0"
    local client_dst_execution="ip netns exec $namespace"

    INITIATE_TRAFFIC_IPERF_PID=""

    if [ -z "$remote" ] || [ -z "$my_ip" ]; then
        fail "Missing arguments for initiate_traffic()"
        return 1
    fi
    if [ "${VDPA}" == "1" ]; then
        server_dst_execution="on_vm1"
        on_vm1 rm -rf $p_server
        client_dst_execution="on_vm2"
        on_vm2 rm -rf $p_client
    fi

    local t=5

    sleep_time=$((t+2))
    if [ "$iperf_cmd" == "iperf" ]; then
        sleep_time=$((t+4))
    fi

    # server
    rm -rf $p_server
    local server_cmd="${server_dst_execution} timeout $sleep_time $iperf_cmd -f Mbits -s"

    if [ "$iperf_cmd" == "iperf" ]; then
        server_cmd+=" -t $((sleep_time-1)) > $p_server 2>&1 &"
    else
        server_cmd+=" -D --logfile $p_server"
    fi

    exec_dbg "$server_cmd"
    sleep 2

    verify_iperf_running

    # client
    rm -rf $p_client
    local cmd="$iperf_cmd -f Mbits -c $my_ip -t $t -P $num_connections &> $p_client"

    if [ -n "$namespace" ]; then
        cmd="${client_dst_execution} $cmd"
    fi

    if [ "$remote" == "remote" ]; then
        cmd="on_remote $cmd"
    fi

    debug "Executing in background | $cmd"
    eval $cmd &
    local pid2=$!
    INITIATE_TRAFFIC_IPERF_PID=$pid2

    # verify pid
    sleep 1
    kill -0 $pid2 &>/dev/null
    if [ $? -ne 0 ]; then
       err "$iperf_cmd failed"
       stop_traffic
       return 1
    fi

    if [ "$remote" == "remote" ]; then
        debug "Check iperf is running on remote"
        verify_iperf_running $remote
    fi
}

function validate_offload() {
    local ip=$1

    if echo $TESTNAME | grep -q -- "-ct-" ; then
        check_offloaded_connections $num_connections
    fi

    wait_traffic

    check_dpdk_offloads $ip
}

function validate_actual_traffic() {
    if [ "${VDPA}" == "1" ]; then
        scp root@${NESTED_VM_IP1}:${p_server} $p_server &> /dev/null
        if [ -n "$namespace"  ]; then
            scp root@${NESTED_VM_IP2}:${p_client} $p_client &> /dev/null
        fi
    fi

    if [ -f $p_server ]; then
        debug "Server traffic:"
        cat $p_server
    else
        err "Missing $p_server, probably a problem with iperf"
    fi

    if [ -f $p_client ]; then
        debug "Client traffic:"
        cat $p_client
    else
        err "Missing $p_client, probably a problem with iperf or ssh"
    fi

    validate_traffic 100
}

function validate_traffic() {
    local min_traffic=$1

    local server_traffic=$(cat $p_server | grep SUM | grep -o "[0-9.]* MBytes/sec" | cut -d " " -f 1 | head -1)
    local client_traffic=$(cat $p_client | grep SUM | grep -o "[0-9.]* MBytes/sec" | cut -d " " -f 1 | head -1)

    debug "Validate traffic server: $server_traffic , client: $client_traffic"
    if [[ -z $server_traffic || $server_traffic < $1 ]]; then
        err "Server traffic is $server_traffic, lower than limit $min_traffic"
    fi

    if [[ -z $client_traffic ||  $client_traffic < $1 ]]; then
        err "Client traffic is $client_traffic, lower than limit $min_traffic"
    fi
}

function stop_traffic() {
    local dst_execution=""

    if [ "${VDPA}" == "1" ]; then
        dst_execution="on_vm1 "
    fi
    exec_dbg "${dst_execution}killall -9 -q $iperf_cmd &>/dev/null"
    exec_dbg "on_remote killall -9 -q $iperf_cmd &>/dev/null"
    sleep 1
}

function wait_traffic() {
    [ -z "$INITIATE_TRAFFIC_IPERF_PID" ] && return

    debug "Wait for iperf pid $INITIATE_TRAFFIC_IPERF_PID"
    if [ "${VDPA}" == "1" ]; then
        on_vm1 wait $INITIATE_TRAFFIC_IPERF_PID
    else
        wait $INITIATE_TRAFFIC_IPERF_PID
    fi
    INITIATE_TRAFFIC_IPERF_PID=""
}

function __cleanup() {
    ip a flush dev $NIC &>/dev/null
    ip a flush dev $NIC2 &>/dev/null
    ip -all netns delete &>/dev/null
    start_clean_openvswitch
}

function remote_cleanup_test() {
    title "Cleaning up remote"
    on_remote_exec __cleanup
}

function cleanup_test() {
    local tunnel_device_name=$1
    __cleanup
    cleanup_e2e_cache
    cleanup_ct_ct_nat_offload
    cleanup_tunnel
    if [ "$tunnel_device_name" != "" ]; then
        cleanup_remote_tunnel
    fi
    cleanup_remote_tunnel $tunnel_device_name
    if [ "${VDPA}" == "1" ]; then
        on_vm1 ip a flush dev $VDPA_DEV_NAME
        on_vm2 ip a flush dev $VDPA_DEV_NAME
    fi
    sleep 0.5
}

function config_local_vlan() {
    local vlan=$1
    local ip=${2:-$LOCAL_TUN_IP}

    ovs-vsctl add-port br-phy pf.$vlan tag=$vlan -- set interface pf.$vlan type=internal
    bf_wrap "ifconfig pf.$vlan $ip/24 up
             ifconfig br-phy 0"
}

function config_remote_vlan() {
    local vlan=$1
    local vlan_dev=$2
    local ip=${3:-$REMOTE_IP}
    on_remote "ip a flush dev $REMOTE_NIC
               ip l set dev $REMOTE_NIC up
               ip link add link $REMOTE_NIC name $vlan_dev type vlan id $vlan
               ip a add $ip/24 dev $vlan_dev
               ip l set dev $vlan_dev up"
}

function config_remote_arm_bridge() {
    local bridge=${1:-br-phy}
    local port=${2:-$NIC}
    local pci=$BF_PCI

    [ $port = $NIC2 ] && pci=$BF_PCI2

    if is_bf_host; then
        title "Configuring simple bridge $bridge over remote arm side"
        on_remote_bf_exec "config_simple_bridge_with_rep 0 true $bridge $port
                           ovs_add_port \"ECPF\" 0 $bridge $pci"
    fi
}

function config_remote_nic() {
    local ip=${1:-$REMOTE_IP}

    title "Configuring remote nic"

    config_remote_arm_bridge
    __config_remote_nic $ip
}

function __config_remote_nic() {
    local ip=$1
    on_remote "ip a flush dev $REMOTE_NIC
               ip a add $ip/24 dev $REMOTE_NIC
               ip l set dev $REMOTE_NIC up"
}

function exec_dbg() {
    debug "${GRAY}Executing | ${NOCOLOR}$@"
    eval "$@"
}

function exec_dbg_on_remote() {
    debug "${GRAY}Executing on remote | ${NOCOLOR}$@"
    on_remote "$@"
}

function config_vlan_device_ns() {
    local dev=$1
    local vlan_dev=$2
    local vlan_id=$3
    local ip=$4
    local vlan_dev_ip=$5
    local ns=${6:-"ns0"}

    local dst_execution="ip netns exec $ns"

    if [ "${VDPA}" == "1" ]; then
        dst_execution="on_vm1"

        if [ "${ns}" != "ns0" ]; then
            dst_execution="on_vm2"
        fi
    fi

    config_ns $ns $dev $ip

    local cmd='${dst_execution} ip link add link $dev name $vlan_dev type vlan id $vlan_id'
    eval $cmd
    cmd='${dst_execution} ip a add $vlan_dev_ip/24 dev $vlan_dev'
    eval $cmd
    cmd='${dst_execution} ip l set $vlan_dev up'
    eval $cmd
}

function verify_ovs_expected_msg() {
    local msg=$1
    local timeout=${2:-10}

    title "Verifying \"$msg\" expected message."

    local end=$((SECONDS+$timeout))
    while [ $SECONDS -lt $end ]; do
        ovs-vsctl show | grep "$msg"
        if [ "$?" == 0 ]; then
            return 0
        fi
    done

    fail "Did not get expected message \"$msg\""
}

function verify_remote_tcpdump_is_running() {
    for _ in `seq 5`; do
       if on_remote pidof -s tcpdump >/dev/null; then
            debug "tcpdump is now running on remote"
            sleep 1
            return
       fi
       sleep 1
    done

    fail "tcpdump is not running on remote"
}
