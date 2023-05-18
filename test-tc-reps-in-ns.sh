#!/bin/bash
#
# Test a device in switchdev mode in a namespace can process traffic on both the HW and SW DPs
#
# Enable SRIOV after PF/uplink rep is moved to a NS. All VF REPs will be created in the NS.
# Then, config VxLAN rules for both fast path and slow path in the NS and use traffic to verify
# that traffic works correctly both in fast and slow path
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_remote_server

NIC_PCI=${PCI_MAP[$NIC]}
UPLINK_IN_NS="eth0"
REP_IN_NS="eth1"
REP2_IN_NS="eth2"
NS="ns0"
VF_NS1="vf_ns1"
VF_NS2="vf_ns2"
VF_IP=1.1.1.7
VF_IP2=2.2.2.7
REMOTE=1.1.1.8
REMOTE2=2.2.2.8

LOCAL_TUN_IP=7.7.7.7
REMOTE_TUN_IP=7.7.7.8
VXLAN="vxlan1"
VXLAN_ID=42
VXLAN_PORT=4789

EXEC_NS="ip netns exec"

function cleanup_remote() {
    on_remote "ip a flush dev $REMOTE_NIC
               ip l del dev $VXLAN &>/dev/null"
}

function cleanup_local() {
    enable_legacy
    config_sriov 0
    for ns in $NS $VF_NS1 $VF_NS2; do
        ip netns del $ns &>/dev/null
    done
    ip a flush dev $NIC 2>/dev/null
    ip l del $VXLAN 2>/dev/null
}

function cleanup() {
    cleanup_remote
    cleanup_local
}
trap cleanup EXIT

function config() {
    cleanup

    for ns in $NS $VF_NS1 $VF_NS2; do
        ip netns add $ns &>/dev/null
    done
    devlink dev reload pci/$NIC_PCI netns $NS
    PF_IN_NS=$NS
    config_sriov 2
    enable_switchdev
    bind_vfs
    PF_IN_NS=""
    ip link set dev $VF netns $VF_NS1
    ip link set dev $VF2 netns $VF_NS2
    $EXEC_NS $VF_NS1 ifconfig $VF $VF_IP/24 up
    $EXEC_NS $VF_NS2 ifconfig $VF2 $VF_IP2/24 up

    $EXEC_NS $NS ifconfig $UPLINK_IN_NS $LOCAL_TUN_IP up
    $EXEC_NS $NS ip link add name $VXLAN type vxlan \
        id $VXLAN_ID dev $UPLINK_IN_NS remote $REMOTE_TUN_IP dstport $VXLAN_PORT

    for inter in $VXLAN $REP_IN_NS $REP2_IN_NS; do
        $EXEC_NS $NS tc qdisc del dev $inter ingress 2>/dev/null
        $EXEC_NS $NS tc qdisc add dev $inter ingress || err "Cannot find interface $inter in ns $NS"
        $EXEC_NS $NS ip link set $inter up
    done

    fail_if_err

    VF_MAC=$($EXEC_NS $VF_NS1 cat /sys/class/net/$VF/address)
    VF2_MAC=$($EXEC_NS $VF_NS2 cat /sys/class/net/$VF2/address)
    config_tc_fastpath_vxlan_rules $REP_IN_NS $VF_MAC $LOCAL_TUN_IP $REMOTE_TUN_IP $VXLAN
    config_tc_slowpath_vxlan_rules $REP2_IN_NS $VF2_MAC $LOCAL_TUN_IP $REMOTE_TUN_IP $VXLAN
}

function config_tc_vxlan_encap_rules() {
    local src_dev=$1
    local src_dev_mac=$2
    local local_ip=$3
    local remote_ip=$4
    local target_dev=$5
    local skip=$6 #optional

    $EXEC_NS $NS tc filter add dev $src_dev protocol ip ingress \
        flower src_mac $src_dev_mac $skip \
        action tunnel_key set src_ip $local_ip dst_ip $remote_ip dst_port $VXLAN_PORT id $VXLAN_ID \
        action mirred egress redirect dev $target_dev
    $EXEC_NS $NS tc filter add dev $src_dev protocol arp ingress \
        flower src_mac $src_dev_mac $skip \
        action mirred egress redirect dev $target_dev
}

function config_tc_fastpath_vxlan_rules() {
    local src_dev=$1
    local src_dev_mac=$2
    local local_ip=$3
    local remote_ip=$4
    local target_dev=$5

    # encap rules for packets from local to remote
    config_tc_vxlan_encap_rules $src_dev $src_dev_mac $local_ip $remote_ip $target_dev

    # decap rules for packets from remote to local
    $EXEC_NS $NS tc filter add dev $target_dev ingress protocol ip \
        flower dst_mac $src_dev_mac enc_src_ip $remote_ip enc_dst_ip $local_ip enc_key_id $VXLAN_ID enc_dst_port $VXLAN_PORT \
        action tunnel_key unset action mirred egress redirect dev $src_dev
    $EXEC_NS $NS tc filter add dev $target_dev ingress protocol arp \
        flower dst_mac $src_dev_mac enc_src_ip $remote_ip enc_dst_ip $local_ip enc_key_id $VXLAN_ID enc_dst_port $VXLAN_PORT \
        action mirred egress redirect dev $src_dev
}

function config_tc_slowpath_vxlan_rules() {
    local src_dev=$1
    local src_dev_mac=$2
    local local_ip=$3
    local remote_ip=$4
    local target_dev=$5

    # encap rules for packets from local to remote
    config_tc_vxlan_encap_rules $src_dev $src_dev_mac $local_ip $remote_ip $target_dev "skip_hw"

    # decap rules for packets from remote to local
    # Rules in SW, packets have been decaped
    $EXEC_NS $NS tc filter add dev $target_dev ingress protocol ip \
        flower dst_mac $src_dev_mac skip_hw action mirred egress redirect dev $src_dev
    $EXEC_NS $NS tc filter add dev $target_dev ingress protocol arp \
        flower dst_mac $src_dev_mac skip_hw action mirred egress redirect dev $src_dev
}

function config_remote() {
    on_remote "ip link del $VXLAN &>/dev/null
               ip link add $VXLAN type vxlan id $VXLAN_ID dev $NIC dstport $VXLAN_PORT
               ip a flush dev $NIC
               ip a add $REMOTE_TUN_IP/24 dev $NIC
               ip a add $REMOTE/24 dev $VXLAN
               ip a add $REMOTE2/24 dev $VXLAN:1
               ip l set dev vxlan1 up
               ip l set dev $NIC up
               arp -i $VXLAN -s $VF_IP $VF_MAC
               arp -i $VXLAN -s $VF_IP2 $VF2_MAC"
}

function run() {
    config
    config_remote

    sleep 2
    title "test ping"
    $EXEC_NS $VF_NS1 ping -q -c 1 -w 1 $REMOTE
    if [ $? -ne 0 ]; then
        err "ping failed"
        return
    fi

    title "test traffic"
    t=15
    on_remote timeout $((t+2)) iperf3 -s -D
    sleep 1
    timeout $((t+2)) $EXEC_NS $VF_NS1 iperf3 -c $REMOTE -t $t -P3 &
    pid2=$!

    # verify pid
    sleep 2
    kill -0 $pid2 &>/dev/null
    if [ $? -ne 0 ]; then
        err "iperf failed"
        return
    fi

    timeout $((t-4)) $EXEC_NS $VF_NS1 tcpdump -qnnei $VF -c 60 'tcp' &
    tpid1=$!
    timeout $((t-4)) $EXEC_NS $NS tcpdump -qnnei $REP_IN_NS -c 10 'tcp' &
    tpid2=$!

    sleep $t
    title "Verify traffic on $VF1 in netns $VF_NS1"
    verify_have_traffic $tpid1
    title "Verify offload on $REP_IN_NS in netns $NS"
    verify_no_traffic $tpid2

    kill -9 $pid1 &>/dev/null
    on_remote killall -9 -q iperf3 &>/dev/null
    echo "wait for background traffic stops"
    wait

    sleep 2
    title "test ping with skip_hw"
    t=10
    $EXEC_NS $VF_NS2 ping -q -c $((t+2)) $REMOTE2 &
    if [ $? -ne 0 ]; then
        err "ping failed"
        return
    fi
    sleep 2
    timeout $t $EXEC_NS $VF_NS2 tcpdump -qnnei $VF2 -c 10 'ip' &
    tpid1=$!
    timeout $t $EXEC_NS $NS tcpdump -qnnei $REP2_IN_NS -c 10 'ip' &
    tpid2=$!
    sleep $((t+1))
    title "Verify traffic on $VF2 in netns $VF_NS2"
    verify_have_traffic $tpid1
    title "Verify not offload on $REP2_IN_NS in netns $NS"
    verify_have_traffic $tpid2
    for inter in $VXLAN $REP_IN_NS $REP2_IN_NS; do
        $EXEC_NS $NS tc qdisc del dev $inter ingress 2>/dev/null
        $EXEC_NS $NS tc qdisc add dev $inter ingress || err "Cannot find interface $inter in ns $NS"
    done
}

run

trap - EXIT
PF_IN_NS=$NS
cleanup
test_done
