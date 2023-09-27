LOCAL_TUN_IP=7.7.7.7
REMOTE_TUNNEL_IP=7.7.7.8
LOCAL_TUN_IP2=8.8.8.7
REMOTE_TUNNEL_IP2=8.8.8.8

TUNNEL_ID=42
TUNNEL_DEV="tunnel1"
TUNNEL_ID2=43
TUNNEL_DEV2="tunnel2"

TCGRE="${DIR}/ovs-dpdk-tests/tcgre.sh"
GRE_ENTROPY=0
REMOTE_GRE_ENTROPY=0

function gre_set_entropy() {
    local pci=$(get_pf_pci)
    local cmd="$TCGRE $pci"
    debug "Run $cmd"
    bf_wrap "$cmd"
    GRE_ENTROPY=1
}

function gre_set_entropy_on_remote() {
    local pci=$(get_pf_pci)
    local cmd="$TCGRE $pci"
    debug "Run on remote $cmd"
    remote_bf_wrap "$cmd"
    REMOTE_GRE_ENTROPY=1
}

function cleanup_remote_tunnel() {
    local tunnel=${1:-$TUNNEL_DEV}
    local physdev=$REMOTE_NIC

    if [ "$tunnel" == "$TUNNEL_DEV2" ]; then
        physdev=$REMOTE_NIC2
    fi

    on_remote "ip a flush dev $physdev
               ip l del dev $tunnel &>/dev/null"
}

function config_remote_tunnel() {
    local tnl_type=$1
    local tunnel_dev=${2:-"$TUNNEL_DEV"}
    local tunnel_id=${3:-"$TUNNEL_ID"}
    local local_tunnel_ip=${4:-"$LOCAL_TUN_IP"}
    local remote_tunnel_ip=${5:-"$REMOTE_TUNNEL_IP"}
    local remote_nic=${6:-"$REMOTE_NIC"}
    local remote_ip=${7:-"$REMOTE_IP"}
    local bridge=${8:-br-phy}
    local port=${9:-$NIC}
    local cmd

    if [ "$tnl_type" == "geneve" ]; then
         cmd="ip link add $tunnel_dev type geneve id $tunnel_id remote $local_tunnel_ip dstport 6081"
    elif [ "$tnl_type" == "gre" ]; then
         cmd="ip link add $tunnel_dev type gretap key $tunnel_id remote $local_tunnel_ip"
    elif [ "$tnl_type" == "vxlan" ]; then
         cmd="ip link add $tunnel_dev type vxlan id $tunnel_id remote $local_tunnel_ip dstport 4789"
    else
         err "Unknown tunnel $tnl_type"
         return 1
    fi

    on_remote "ip link del $tunnel_dev &>/dev/null
               $cmd
               ip a flush dev $remote_nic
               ip a add $remote_tunnel_ip/24 dev $remote_nic
               ip a add $remote_ip/24 dev $tunnel_dev
               ip l set dev $tunnel_dev up
               ip link set dev $tunnel_dev mtu 1400
               ip l set dev $remote_nic up"

    config_remote_arm_bridge $bridge $port
}

function config_tunnel() {
    local tnl_type=$1
    local reps=${2:-1}
    local br=${3:-"br-phy"}
    local remote_br=${4:-"br-int"}
    local tnl_id=${5:-"$TUNNEL_ID"}
    local local_ip=${6:-"$LOCAL_IP"}
    local remote_tnl_ip=${7:-"$REMOTE_TUNNEL_IP"}
    local dev=${8:-"$VF"}
    local nic=${9:-"$NIC"}
    local pci=$(get_pf_pci)

    if [ $nic == $NIC2 ]; then
        pci=$(get_pf_pci2)
    fi

    local dst_execution="ip netns exec ns0"
    if [ "${VDPA}" == "1" ]; then
        dst_execution="on_vm1"
        dev=$VDPA_DEV_NAME
    fi
    config_simple_bridge_with_rep 0 true $br $nic
    config_remote_bridge_tunnel $tnl_id $remote_tnl_ip $tnl_type $reps $remote_br $pci
    start_vdpa_vm
    config_ns ns0 $dev $local_ip
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

    local cmd="require_interfaces REP NIC
               unbind_vfs
               bind_vfs
               config_ns ns0 $VF $vf_ip
               ip netns exec ns0 ifconfig $VF mtu 1400"

    local bridge_create_cmd="config_simple_bridge_with_rep 0
                             config_remote_bridge_tunnel $TUNNEL_ID $wanted_remote_ip $tnl_type
                             config_local_tunnel_ip $wanted_local_ip br-phy"

     if [ "$remote" == "remote" ]; then
        title "Configuring remote server"
        on_remote_exec "$cmd"
        remote_bf_wrap_exec "$bridge_create_cmd"
     else
         title "Configuring local server"
         eval "$cmd"
         bf_wrap_exec "$bridge_create_cmd"
     fi
}
