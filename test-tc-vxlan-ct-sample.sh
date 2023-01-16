#!/bin/bash
#
# Test if iperf works for vxlan ct and sample rule.
#
# Bug SW #3262983: sFlow with connection tracking over vxlan traffic will not pass
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_remote_server
require_module act_sample psample
compile_psample

IP=1.1.1.7
REMOTE=1.1.1.8

LOCAL_TUN=7.7.7.7
REMOTE_IP=7.7.7.8
VXLAN_ID=42
DSTPORT=4789

function cleanup() {
    ip netns del ns0 2> /dev/null
    reset_tc $REP
    ip link del dev vxlan1 2> /dev/null
    cleanup_remote_vxlan
}
trap cleanup EXIT

function run() {
    reset_tc $NIC $REP vxlan1
    local file=/tmp/psample.txt
    local file2=/tmp/iperf.txt
    local n=10

    echo "add arp rules"
    tc_filter add dev $REP protocol arp parent ffff: prio 1 flower skip_hw    \
        action tunnel_key set \
        src_ip $LOCAL_TUN     \
        dst_ip $REMOTE_IP     \
        dst_port $DSTPORT     \
        id $VXLAN_ID          \
        action mirred egress redirect dev vxlan1
    tc_filter add dev vxlan1 protocol arp parent ffff: prio 1 flower skip_hw  \
        enc_src_ip $REMOTE_IP        \
        enc_dst_ip $LOCAL_TUN        \
        enc_dst_port $DSTPORT        \
        enc_key_id $VXLAN_ID         \
        action tunnel_key unset pipe \
        action mirred egress redirect dev $REP

    echo "add vxlan ct sample rules"
    tc_filter add dev $REP protocol ip parent ffff: chain 0 prio 2 flower \
        ct_state -trk       \
        action ct pipe      \
        action goto chain 1

    tc_filter add dev $REP protocol ip parent ffff: chain 1 prio 3 flower \
        ct_state +trk+new     \
        action ct commit      \
        action tunnel_key set \
        src_ip $LOCAL_TUN     \
        dst_ip $REMOTE_IP     \
        dst_port $DSTPORT     \
        id $VXLAN_ID          \
        action mirred egress redirect dev vxlan1

    tc_filter add dev $REP protocol ip parent ffff: chain 1 prio 4 flower \
        ct_state +trk+est     \
        action tunnel_key set \
        src_ip $LOCAL_TUN     \
        dst_ip $REMOTE_IP     \
        dst_port $DSTPORT     \
        id $VXLAN_ID          \
        action mirred egress redirect dev vxlan1

    verify_in_hw $REP 2
    verify_in_hw $REP 4
    fail_if_err

    tc_filter add dev vxlan1 protocol ip parent ffff: chain 0 prio 2 flower \
        enc_src_ip $REMOTE_IP        \
        enc_dst_ip $LOCAL_TUN        \
        enc_dst_port $DSTPORT        \
        enc_key_id $VXLAN_ID         \
        ct_state -trk                \
        action sample rate 1 group 6 \
        action ct pipe               \
        action goto chain 1

    tc_filter add dev vxlan1 protocol ip  parent ffff: chain 1 prio 3 flower \
        enc_src_ip $REMOTE_IP   \
        enc_dst_ip $LOCAL_TUN   \
        enc_dst_port $DSTPORT   \
        enc_key_id $VXLAN_ID    \
        ct_state +trk+new       \
        action ct commit        \
        action tunnel_key unset \
        action mirred egress redirect dev $REP

    tc_filter add dev vxlan1 protocol ip  parent ffff: chain 1 prio 4 flower \
        enc_src_ip $REMOTE_IP   \
        enc_dst_ip $LOCAL_TUN   \
        enc_dst_port $DSTPORT   \
        enc_key_id $VXLAN_ID    \
        ct_state +trk+est       \
        action tunnel_key unset \
        action mirred egress redirect dev $REP

    verify_in_hw vxlan1 2
    verify_in_hw vxlan1 4
    fail_if_err

    pkill psample
    timeout -k 1 2 $psample_dir/psample -n $n > $file &
    pid=$!

    title "run ping"
    ip netns exec ns0 ping -q -c $n -i 0.1 -w 2 $REMOTE || err "Ping failed"
    c=$(grep iifindex $file | wc -l)
    (( c < n )) && err "expect to get $n sampled packets, got $c"

    wait $pid
    fail_if_err

    title "run iperf"
    t=5
    on_remote timeout $((t+2)) iperf -s -t $t &
    sleep 2
    ip netns exec ns0 timeout $((t+2)) iperf -c $REMOTE -t $t -i 1 -y c -b 1G | tee $file2
    # bandwidth is 1G, expect bigger than 0.5G.
    c=$(awk -F, '$NF>500000000 {print $NF}' $file2 | wc -l)
    (( c < t )) && err "iperf failed, no traffic"
}

function config_vxlan() {
    echo "config vxlan dev"
    ip link add vxlan1 type vxlan dstport $DSTPORT external
    ip link set vxlan1 up
    ifconfig $NIC $LOCAL_TUN/24 up
}

config_sriov 1
enable_switchdev
unbind_vfs
bind_vfs
require_interfaces REP VF NIC
config_vxlan
config_vf ns0 $VF $REP $IP
reset_tc $NIC $REP vxlan1
config_remote_vxlan

run

test_done
