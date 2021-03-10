#!/bin/bash
#
# Test OVS CT TCP traffic
#
# IGNORE_FROM_TEST_ALL

my_dir="$(dirname "$0")"
. $my_dir/common.sh
testpmd="$DIR/testpmd/testpmd"
pktgen="$DIR/network-testing/pktgen/pktgen_sample04_many_flows.sh"

require_module act_ct pktgen
require_remote_server
echo 0 > /proc/sys/net/netfilter/nf_conntrack_tcp_be_liberal

IP1="1.1.1.7"
IP2="1.1.1.8"

LOCAL_TUN=7.7.7.7
REMOTE_IP=7.7.7.8
VXLAN_ID=42

config_sriov 2
enable_switchdev
unbind_vfs
bind_vfs
mac2=`on_remote cat /sys/class/net/$REMOTE_NIC/address`

pid_pktgen=""
function kill_pktgen() {
    test $pid_pktgen || return
    [ -e /proc/$pid_pktgen ] || return
    kill $pid_pktgen
    wait $pid_pktgen 2>/dev/null
    pid_pktgen=""
}

pid_testpmd=""
function kill_testpmd() {
    test $pid_testpmd || return
    [ -e /proc/$pid_testpmd ] || return
    kill $pid_testpmd
    wait $pid_testpmd 2>/dev/null
    pid_testpmd=""
}

function cleanup_remote() {
    on_remote ip a flush dev $REMOTE_NIC
    on_remote ip l del dev vxlan1 &>/dev/null
}

function cleanup() {
    kill_testpmd
    kill_pktgen
    conntrack -F

    ip netns del ns0 2> /dev/null
    reset_tc $REP

    cleanup_remote
}
trap cleanup EXIT

function run_pktgen() {
    echo "run traffic"
    # with different number of threads we get different result
    # -t 10 cpu hogs and getting ~50k flows. reproduced the kfree(ft) and rhashtable rehash race
    # -t 1 got ~260k flows
    # -t 2 got ~520k flows
    ip netns exec ns0 timeout --kill-after=1 $t $pktgen -i $VF -t 1 -d $IP2 -m $mac2 &
    pid_pktgen=$!
    sleep 4
    if [ ! -e /proc/$pid_pktgen ]; then
        pid_pktgen=""
        err "pktgen failed"
        return 1
    fi
    return 0
}

function run_testpmd() {
    echo "run fwder"
    on_remote "ip link set dev $REMOTE_NIC up"
    on_remote "echo 512 > /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages"
    on_remote "timeout --kill-after=10 $t tail -f /dev/null | \
               $testpmd --no-pci --vdev=eth_af_packet0,iface=vxlan1 -- --forward-mode=5tswap -a" &
    pid_testpmd=$!
    sleep 5
    if [ ! -e /proc/$pid_testpmd ]; then
        pid_testpmd=""
        err "testpmd failed"
        return 1
    fi
    return 0
}

function config_remote() {
    on_remote ip link del vxlan1 &>/dev/null
    on_remote ip link add vxlan1 type vxlan id $VXLAN_ID dev $REMOTE_NIC dstport 4789
    on_remote ip a flush dev $REMOTE_NIC
    on_remote ip a add $REMOTE_IP/24 dev $REMOTE_NIC
    on_remote ip a add $IP2/24 dev vxlan1
    on_remote ip l set dev vxlan1 up
    on_remote ip l set dev $REMOTE_NIC up
}

function config_ovs() {
    echo "setup ovs"
    start_clean_openvswitch

    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs vxlan1 -- set interface vxlan1 type=vxlan options:local_ip=$LOCAL_TUN options:remote_ip=$REMOTE_IP options:key=$VXLAN_ID options:dst_port=4789
}

function reconfig_flows() {
    ovs-ofctl del-flows br-ovs
    ovs-ofctl add-flow br-ovs arp,actions=normal
    ovs-ofctl add-flow br-ovs icmp,actions=normal
    ovs-ofctl add-flow br-ovs "table=0, ip,ct_state=-trk,udp actions=ct(zone=12,table=1)"
    ovs-ofctl add-flow br-ovs "table=0, ip,ct_state=-trk,tcp actions=ct(zone=12,table=1)"
    ovs-ofctl add-flow br-ovs "table=1, ip,ct_state=+trk+new actions=ct(zone=12,commit),normal"
    ovs-ofctl add-flow br-ovs "table=1, ip,ct_state=+trk+est,ct_zone=12 actions=normal"
}

function verify_counter() {
    sysfs_counter="/sys/kernel/debug/mlx5/$PCI/ct/offloaded"
    if [ -f $sysfs_counter ]; then
        log "check count"
        a=`cat $sysfs_counter`
        echo $a
        if [ $a -lt 1000 ]; then
            err "low count"
        fi
    else
        warn "Cannot check offloaded count"
    fi
#    cat /proc/net/nf_conntrack | grep --color=auto -i offload
}

function run() {
    title "Test OVS CT TCP"

    ifconfig $NIC $LOCAL_TUN/24 up
    config_vf ns0 $VF $REP $IP1
    config_remote
    config_ovs
    reconfig_flows
    ovs-ofctl dump-flows br-ovs --color

    echo "prepare for offload"
    #echo 600 > /sys/module/nf_flow_table/parameters/nf_flow_offload_timeout
    sysctl -w 'net.netfilter.nf_conntrack_max=524288'

    echo "add zone 12 rule for priming offload callbacks"
    tc_filter add dev $REP prio 1337 proto ip chain 1337 ingress flower \
        skip_sw ct_state -trk action ct zone 12 pipe \
        action mirred egress redirect dev $NIC

    echo "sleep 3 sec, fg now"
    sleep 3

    t=300
    echo "running for $t seconds"
    run_testpmd || return
    run_pktgen || return
    w=100
    sleep $w
    let t-=w
    echo "start tcpdump"
    timeout $t tcpdump -qnnei $NIC -c 20 udp &
    tpid=$!
    verify_no_traffic $tpid
    sleep 10

    verify_counter

    log "flush"
    kill_pktgen
    kill_testpmd
    ovs-vsctl del-br br-ovs
}


cleanup
run
cleanup
trap - EXIT
test_done
