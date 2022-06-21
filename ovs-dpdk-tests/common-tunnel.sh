LOCAL_TUN_IP=7.7.7.7
REMOTE_TUNNEL_IP=7.7.7.8

TUNNEL_ID=42
TUNNEL_DEV="tunnel1"

TCGRE="${DIR}/ovs-dpdk-tests/tcgre.sh"

function gre_set_entropy() {
    local cmd="$TCGRE $PCI"
    debug "Run $cmd"
    eval "$cmd"
}

function gre_set_entropy_on_remote() {
    local cmd="$TCGRE $PCI"
    debug "Run on remote $cmd"
    on_remote "$cmd"
}

function cleanup_remote_tunnel() {
    local tunnel=${1:-$TUNNEL_DEV}
    on_remote "ip a flush dev $REMOTE_NIC
               ip l del dev $TUNNEL_DEV &> /dev/null
               ip l del dev $tunnel &>/dev/null"
}

function config_remote_tunnel() {
    local tnl_type=$1

    on_remote ip link del $TUNNEL_DEV &>/dev/null

    if [ "$tnl_type" == "geneve" ]; then
         on_remote ip link add $TUNNEL_DEV type geneve id $TUNNEL_ID remote $LOCAL_TUN_IP dstport 6081
    elif [ "$tnl_type" == "gre" ]; then
         on_remote ip link add $TUNNEL_DEV type gretap key $TUNNEL_ID remote $LOCAL_TUN_IP
    elif [ "$tnl_type" == "vxlan" ]; then
         on_remote ip link add $TUNNEL_DEV type vxlan id $TUNNEL_ID remote $LOCAL_TUN_IP dstport 4789
    else
         err "Unknown tunnel $tnl_type"
         return 1
    fi

    on_remote "ip a flush dev $REMOTE_NIC
               ip a add $REMOTE_TUNNEL_IP/24 dev $REMOTE_NIC
               ip a add $REMOTE_IP/24 dev $TUNNEL_DEV
               ip l set dev $TUNNEL_DEV up
               ip link set dev $TUNNEL_DEV mtu 1400
               ip l set dev $REMOTE_NIC up"
}

function config_tunnel() {
    local tnl_type=$1
    local reps=${2:-1}
    local dev=$VF

    local dst_execution="ip netns exec ns0"
    if [ "${VDPA}" == "1" ]; then
        dst_execution="on_vm $NESTED_VM_IP1"
        dev=$VDPA_DEV_NAME
    fi
    config_simple_bridge_with_rep 0
    config_remote_bridge_tunnel $TUNNEL_ID $REMOTE_TUNNEL_IP $tnl_type $reps
    start_vdpa_vm
    config_ns ns0 $VF $LOCAL_IP
    local cmd="${dst_execution} ip link set dev $dev mtu 1400"
    eval $cmd
}

function config_2_side_tunnel() {
    local tnl_type=$1
    create_tunnel_config "local" $REMOTE_TUNNEL_IP $LOCAL_TUN_IP $LOCAL_IP $tnl_type
    create_tunnel_config "remote" $LOCAL_TUN_IP $REMOTE_TUNNEL_IP $REMOTE_IP $tnl_type
}

function create_tunnel_config() {
    local remote=$1
    local wanted_remote_ip=$2
    local wanted_local_ip=$3
    local vf_ip=$4
    local tnl_type=$5

    local cmd="config_sriov 2
               require_interfaces REP NIC
               unbind_vfs
               bind_vfs
               set_e2e_cache_enable false
               start_clean_openvswitch
               config_simple_bridge_with_rep 0
               config_remote_bridge_tunnel $TUNNEL_ID $wanted_remote_ip $tnl_type
               config_local_tunnel_ip $wanted_local_ip br-phy
               config_ns ns0 $VF $vf_ip
               ip netns exec ns0 ifconfig $VF mtu 1400"

     if [ "$remote" == "remote" ]; then
        title "Configuring remote server"
        on_remote_dt "$cmd
                      ovs_conf_set hw-offload false"
     else
         title "Configuring local server"
         eval "$cmd"
     fi
}
