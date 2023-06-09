#!/bin/bash
#
# Test TC rules to enacp/decap vxlan gbp option can be offloaded correctly
# with vxlan traffic.
#
# RM 3291721 VxLAN GBP offload
#
# 1. Config vxlan and enable gbp
# 2. Add tc rules to encap gbp option to vxlan traffic
# 3. Send traffic over vxlan
# 4. Check the traffic is offloaded correctly
#    On remote, ip table rule for output will add gbp option to ip packets
#    On local, tc rules will encap gbp option to ip packets and filter packets
#    according to gbp option
#
# This test needs kernel 5.5+
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_remote_server

IP=1.1.1.7
REMOTE=1.1.1.8

LOCAL_TUN=7.7.7.7
REMOTE_IP=7.7.7.8
VXLAN_ID=42
DSTPORT=4789
VXLAN="vxlan$VXLAN_ID"
GBP_OPT_OUT="0x200"
GBP_OPT_IN="0x400"
VXLAN_OPTIONS="gbp"

config_sriov 2
enable_switchdev
require_interfaces REP NIC
unbind_vfs
bind_vfs

function cleanup_remote() {
    cleanup_remote_vxlan
    on_remote "iptables -D OUTPUT -p ip -j MARK --set-mark $GBP_OPT_IN 2>/dev/null
               iptables -D INPUT -m mark --mark $GBP_OPT_OUT -j ACCEPT 2>/dev/null"
}

function cleanup_local() {
    ip link del $VXLAN &>/dev/null
    ip a flush dev $NIC
    ip netns del ns0 &>/dev/null
    reset_tc $REP
}

function cleanup() {
    cleanup_local
    cleanup_remote
    sleep 0.5
}
trap cleanup EXIT

function config_remote() {
    config_remote_vxlan
    on_remote "iptables -I OUTPUT -p ip -j MARK --set-mark $GBP_OPT_IN
               iptables -I INPUT -m mark --mark $GBP_OPT_OUT -j ACCEPT"
}

function config_local() {
    cleanup
    ifconfig $NIC $LOCAL_TUN/24 up
    ip link add name $VXLAN type vxlan dev $NIC dstport $DSTPORT gbp external
    for i in $REP $VXLAN; do
            ifconfig $i up
            reset_tc $i
    done
    config_vf ns0 $VF $REP $IP

    # encap rules for packets from local to remote
    tc filter add dev $REP protocol ip ingress flower \
        action tunnel_key set src_ip $LOCAL_TUN dst_ip $REMOTE_IP dst_port $DSTPORT id $VXLAN_ID vxlan_opts $GBP_OPT_OUT \
        action mirred egress redirect dev $VXLAN
    local gbp_action_rule_cnt=`tc -s filter show dev $REP ingress | grep -E "vxlan_opts [[:digit:]]+" | wc -l`
    if [ $gbp_action_rule_cnt -ne 1 ]; then
        fail "Failed to offload vxlan gbp action rule"
    fi
    tc filter add dev $REP protocol arp ingress flower \
        action tunnel_key set src_ip $LOCAL_TUN dst_ip $REMOTE_IP dst_port $DSTPORT id $VXLAN_ID \
        action mirred egress redirect dev $VXLAN

    # decap rules for packets from remote to local
    tc filter add dev $VXLAN protocol ip ingress flower enc_key_id $VXLAN_ID enc_dst_port $DSTPORT vxlan_opts $GBP_OPT_IN \
        action tunnel_key unset action mirred egress redirect dev $REP
    local gbp_match_rule_cnt=`tc -s filter show dev $VXLAN ingress | grep -E "vxlan_opts [[:digit:]]+/[[:digit:]]+" | wc -l`
    if [ $gbp_match_rule_cnt -ne 1 ]; then
        fail "Failed to offload vxlan gbp match rule"
    fi
    tc filter add dev $VXLAN protocol arp ingress flower enc_key_id $VXLAN_ID enc_dst_port $DSTPORT \
        action tunnel_key unset action mirred egress redirect dev $REP
}

function run() {
    # icmp
    ip netns exec ns0 ping -q -c 1 -w 2 $REMOTE
    if [ $? -ne 0 ]; then
        err "ping failed"
        return
    fi

    t=15

    ip netns exec ns0 timeout $((t-4)) tcpdump -qnnei $VF -c 30 'tcp' &
    tpid2=$!

    # traffic
    on_remote timeout $((t+2)) iperf3 -s -D

    ip netns exec ns0 timeout $((t+2)) iperf3 -c $REMOTE -t $t -P3 &
    pid2=$!

    # verify pid
    sleep 2
    kill -0 $pid2 &>/dev/null
    if [ $? -ne 0 ]; then
        err "iperf3 failed"
        return
    fi

    timeout $((t-4)) tcpdump -qnnei $REP -c 10 'tcp' &
    tpid=$!

    sleep $t

    title "Verify traffic on $VF"
    verify_have_traffic $tpid2

    title "Verify no traffic on $REP"
    verify_no_traffic $tpid

    killall -9 -q iperf3
    on_remote killall -9 -q iperf3
    echo "wait for bgs"
    wait
}

config_local
config_remote
sleep 2
run
test_done
