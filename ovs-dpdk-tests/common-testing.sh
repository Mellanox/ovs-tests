p_server=/tmp/perf_server
p_client=/tmp/perf_client

function ovs_add_ct_rules() {
    local bridge=${1:-"br-int"}
    ovs-ofctl del-flows $bridge
    ovs-ofctl add-flow $bridge "arp,actions=NORMAL"
    ovs-ofctl add-flow $bridge "table=0,ip,ct_state=-trk,actions=ct(zone=5, table=1)"
    ovs-ofctl add-flow $bridge "table=1,ip,ct_state=+trk+new,actions=ct(zone=5, commit),NORMAL"
    ovs-ofctl add-flow $bridge "table=1,ip,ct_state=+trk+est,ct_zone=5,actions=normal"
    echo "OVS flow rules:"
    ovs-ofctl dump-flows $bridge --color
}

function ovs_add_ct_rules_dec_ttl() {
    local bridge=${1:-"br-int"}
    ovs-ofctl del-flows $bridge
    ovs-ofctl add-flow $bridge "arp,actions=NORMAL"
    ovs-ofctl add-flow $bridge "table=0,ip,ct_state=-trk,actions=ct(zone=5, table=1)"
    ovs-ofctl add-flow $bridge "table=1,ip,ct_state=+trk+new,actions=ct(zone=5, commit),dec_ttl,NORMAL"
    ovs-ofctl add-flow $bridge "table=1,ip,ct_state=+trk+est,ct_zone=5,actions=dec_ttl,normal"
    echo "OVS flow rules:"
    ovs-ofctl dump-flows $bridge --color
}

function verify_ping() {
    local remote_ip=${1:-$REMOTE_IP}
    local namespace=${2:-ns0}
    echo "Testing ping $remote_ip in namespace $namespace"
    ip netns exec $namespace ping -q -c 10 -W 2 -i 0.01 $remote_ip
    if [ $? -ne 0 ]; then
        err "ping failed"
        return 1
    fi
}

function generate_traffic() {
    local remote=${1:-"local"}
    local my_ip=${2:-$LOCAL_IP}
    local namespace=$3
    local t=5

    echo -e "\nTesting TCP traffic remote = $remote , ip = $my_ip , namespace = $namespace"

    # server
    rm -rf $p_server
    ip netns exec ns0 timeout $((t+2)) iperf3 -f Mbits -s -D --logfile $p_server
    sleep 2
    # client
    rm -rf $p_client
    local cmd="iperf3 -f Mbits -c $my_ip -t $t -P 5 &> $p_client"
    if [ -n "$namespace" ]; then
        cmd="ip netns exec $namespace $cmd"
    fi

    if [ "$remote" == "remote" ]; then
        cmd="on_remote $cmd"
    fi

    eval $cmd &
    local pid2=$!

    # verify pid
    sleep 1
    kill -0 $pid2 &>/dev/null
    if [ $? -ne 0 ]; then
       err "iperf3 failed"
       return 1
    fi

    sleep $t

    if [ -f $p_server ]; then
        echo "Server traffic"
        cat $p_server
    else
        err "no $p_server , probably problem with iperf"
    fi

    if [ -f $p_client ]; then
        echo "Client traffic"
        cat $p_client
    else
        err "no $p_client , probably problem with iperf or ssh problem"
    fi

    validate_traffic 1
    kill_iperf
}

function validate_traffic() {
    local min_traffic=$1

    local server_traffic=$(cat $p_server | grep "SUM" | grep "MBytes/sec" | awk '{print $6}' | head -1)
    local client_traffic=$(cat $p_client | grep "SUM" | grep "MBytes/sec" | awk '{print $6}' | head -1)

    echo "validate traffic server: $server_traffic , client: $client_traffic"
    if [[ -z $server_traffic || $server_traffic < $1 ]]; then
        err "server traffic is $server_traffic, lower than limit $min_traffic"
    fi

    if [[ -z $client_traffic ||  $client_traffic < $1 ]]; then
        err "client traffic is $client_traffic, lower than limit $min_traffic"
    fi
}

function kill_iperf() {
   killall -9 iperf3 &>/dev/null
   sleep 1
}

function remote_ovs_cleanup() {
    title "Cleaning up remote"
    on_remote_dt "ip a flush dev $NIC
                  ip netns del ns0 &>/dev/null
                  start_clean_openvswitch"
}

function cleanup_test() {
    local tunnel_device_name=$1
    ip a flush dev $NIC
    ip -all netns delete &>/dev/null
    cleanup_e2e_cache
    cleanup_remote_tunnel $tunnel_device_name
    sleep 0.5
}

function config_remote_vlan() {
    local vlan=$1
    local vlan_dev=$2
    local ip=${3:-$REMOTE_IP}
    on_remote "ip a flush dev $REMOTE_NIC
           ip link add link $REMOTE_NIC name $vlan_dev type vlan id $vlan
           ip a add $ip/24 dev $vlan_dev
           ip l set dev $vlan_dev up"
}

function config_remote_nic() {
    on_remote ip a flush dev $REMOTE_NIC
    on_remote ip a add $REMOTE_IP/24 dev $REMOTE_NIC
    on_remote ip l set dev $REMOTE_NIC up
}
