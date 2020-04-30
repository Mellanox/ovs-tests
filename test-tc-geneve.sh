#!/bin/bash
#
# Test geneve with tc rules
#


my_dir="$(dirname "$0")"
. $my_dir/common.sh

REMOTE_SERVER=${REMOTE_SERVER:-$1}
REMOTE_NIC=${REMOTE_NIC:-$2}

require_remote_server

ip1="7.7.7.1"
ip2="7.7.7.2"
tun_loc="2.2.2.1"
tun_rem="2.2.2.2"
geneve_port=6081

function cleanup_remote() {
    on_remote ip a flush dev $REMOTE_NIC
    on_remote ip l del dev geneve1 &>/dev/null
    on_remote ip link del vm &>/dev/null
}

function kill_iperf() {
    killall -9 iperf3 &>/dev/null && killall -9 iperf3 &>/dev/null
}

function cleanup() {
    kill_iperf
    sleep 1
    ip link del geneve1 2>/dev/null
    reset_tc $REP
    reset_tc $NIC

    cleanup_remote
}


enable_switchdev_if_no_rep $REP
require_interfaces REP
unbind_vfs
bind_vfs
cleanup
trap cleanup EXIT

function config_remote() {
    on_remote ip link del geneve1 2>/dev/null
    on_remote ip link add geneve1 type geneve dstport $geneve_port external
    if [ $? != 0 ]; then
        err "Failed to create remote geneve interface"
        return
    fi
    on_remote ip a flush dev $REMOTE_NIC || err "Failed to config remote $REMOTE_NIC"
    on_remote ip a add $tun_rem/24 dev $REMOTE_NIC
    on_remote ip l set dev geneve1 up
    on_remote ip l set dev $REMOTE_NIC up
    on_remote tc qdisc add dev geneve1 ingress
}

function config_geneve() {
    local dev=$1
    local tun=$2

    echo "Config geneve on $dev ($tun)"
    ip addr flush dev $dev

    ifconfig $dev $tun/24 up
    ip link del geneve1 &>/dev/null
    ip link add geneve1 type geneve dstport $geneve_port external
    ifconfig geneve1 0 up
    tc qdisc add dev geneve1 ingress
}

function no_pkts() {
    dev=$1
    chain=$2
    prio=$3
    t=$4

    title "Verify that $dev has no $t packets on rule chain $chain prio $prio"
    tc -s filter show dev $dev chain $chain prio $prio ingress | grep -i "$t" | grep -q "0 pkt" || err "$dev has $t packets on rule chain $chain prio $prio"
}

function has_pkts() {
    dev=$1
    chain=$2
    prio=$3
    t=$4

    title "Verify that $dev has $t packets on rule chain $chain prio $prio"
    tc -s filter show dev $dev chain $chain prio $prio ingress | grep -i "$t" | grep -q -P "[1-9][0-9]* pkt" || err "$dev has no $t packets on rule chain $chain prio $prio"
}

function run() {
    local geneve_opts="geneve_opts 1234:56:0708090a"

    title "Test geneve"

    config_remote
    config_geneve $NIC $tun_loc
    fail_if_err

    ifconfig $VF $ip1/24 mtu 1400 up
    ifconfig $REP 0 promisc up
    tc_test_verbose

    title "Setup remote geneve + opts"
    on_remote ip link add vm type veth peer name vm_rep
    on_remote ifconfig vm $ip2/24 up
    on_remote ifconfig vm_rep 0 promisc up
    on_remote tc qdisc add dev vm_rep ingress
    on_remote tc filter add dev vm_rep ingress proto ip flower skip_hw action tunnel_key set src_ip 0.0.0.0 dst_ip $tun_loc id 48 dst_port $geneve_port $geneve_opts pipe action mirred egress redirect dev geneve1
    on_remote tc filter add dev vm_rep ingress proto arp flower skip_hw action tunnel_key set src_ip 0.0.0.0 dst_ip $tun_loc id 48 dst_port $geneve_port $geneve_opts pipe action mirred egress redirect dev geneve1
    on_remote tc filter add dev geneve1 ingress protocol arp flower skip_hw action mirred egress redirect dev vm_rep
    on_remote tc filter add dev geneve1 ingress protocol ip flower skip_hw action mirred egress redirect dev vm_rep

    title "Add arp rules"
    tc_filter add dev $REP ingress protocol arp chain 0 prio 2 flower skip_hw \
        action tunnel_key set src_ip 0.0.0.0 dst_ip $tun_rem id 48 dst_port "$geneve_port" pipe \
        action mirred egress redirect dev geneve1

    tc_filter add dev geneve1 ingress protocol arp chain 0 prio 2 flower skip_hw \
        enc_src_ip $tun_rem enc_dst_ip $tun_loc enc_key_id 48 enc_dst_port $geneve_port \
        action mirred egress redirect dev $REP

    # OUTGOING
    title "REP chain 0 SEND"
    tc_filter add dev $REP ingress protocol ip chain 0 prio 1 flower $tc_verbose \
        action tunnel_key set src_ip 0.0.0.0 dst_ip $tun_rem id 48 dst_port $geneve_port $geneve_opts pipe \
        action mirred egress redirect dev geneve1

    # INCOMING CHAIN 0
    title "TCP, dst_port 5000, match geneve opts, in hardware"
    tc_filter add dev geneve1 ingress protocol ip chain 0 prio 1 flower $tc_verbose \
        enc_src_ip $tun_rem enc_dst_ip $tun_loc enc_key_id 48 enc_dst_port $geneve_port $geneve_opts \
        ip_proto tcp dst_port 5000 \
        action mirred egress redirect dev $REP

    title "skip_hw - capture packets that we decapsulated but didn't restore tunnel dev"
    tc_filter add dev $NIC ingress protocol ip chain 0 prio 1 flower dst_ip $ip1 skip_hw action drop

    fail_if_err

    tc -s filter show dev geneve1 ingress chain 0 proto ip > /tmp/chain0_geneve_dump
    tc -s filter show dev $REP ingress chain 0 proto ip > /tmp/chain0_rep_dump
    tc -s filter show dev $NIC ingress chain 0 proto ip > /tmp/chain0_nic_dump
    i=0 && mlxdump -d $PCI fsdump --type FT --gvmi=$i --no_zero > /tmp/port$i || err "mlxdump failed"

    title "Test tunnel connectivity"
    ping $tun_rem -c 1 -w 1 || err "ping failed"
    n=`ip n | grep $tun_rem | cut -d " " -f 1-5`
    ip n r $n
    on_remote ping $tun_loc -c 1 -w 1

    fail_if_err

    title "Run traffic"
    iperf3 -s -p 5000 -1 &

    title "Traffic fully in hardware, match on geneve without opts"
    on_remote timeout 10 iperf3 -c $ip1 -t 5 -p 5000 || err "failed iperf3 port 5000"

    fail_if_err

    title "Verify tc stats"
    sleep 3

    tc -s filter show dev geneve1 ingress chain 0 proto ip > /tmp/chain0_geneve_dump
    tc -s filter show dev $REP ingress chain 0 proto ip > /tmp/chain0_rep_dump

    no_pkts geneve1 0 1 software
    has_pkts geneve1 0 1 hardware
}


start_check_syndrome
run
check_syndrome
test_done
