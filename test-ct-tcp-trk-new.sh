#!/bin/bash
#
# Test CT +trk+new offload
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module act_ct

REMOTE_SERVER=${REMOTE_SERVER:-$1}
REMOTE_NIC=${REMOTE_NIC:-$2}

require_remote_server

IP=1.1.1.7
REMOTE=1.1.1.8

LOCAL_TUN=7.7.7.7
REMOTE_IP=7.7.7.8
VXLAN_ID=42

enable_switchdev
require_interfaces REP
unbind_vfs
bind_vfs
reset_tc $NIC

VF_MAC=`cat /sys/class/net/$VF/address`
NIC_MAC=`cat /sys/class/net/$NIC/address`

test "$VF_MAC" || fail "no vf mac"
test "$NIC_MAC" || fail "no nic mac"

function cleanup_remote() {
    on_remote ip a flush dev $REMOTE_NIC
    on_remote ip l del dev vxlan1 &>/dev/null
}

function cleanup() {
    cleanup_remote
    ip a flush dev $NIC
    ip netns del ns0 2> /dev/null
    reset_tc $NIC
}
trap cleanup EXIT

function config_remote() {
    on_remote ip link del vxlan1 &>/dev/null
    on_remote ip link add vxlan1 type vxlan id $VXLAN_ID dev $REMOTE_NIC remote $LOCAL_TUN dstport 4789
    on_remote ip a flush dev $REMOTE_NIC
    on_remote ip a add $REMOTE_IP/24 dev $REMOTE_NIC
    on_remote ip a add $REMOTE/24 dev vxlan1
    on_remote ip l set dev vxlan1 up
    on_remote ip l set dev $REMOTE_NIC up
    # static arps
    on_remote ip n r $IP dev vxlan1 lladdr $VF_MAC
    on_remote ip n r $LOCAL_TUN dev $REMOTE_NIC lladdr $NIC_MAC
}

function run() {
    title "Test CT +trk+new"
    tc_test_verbose
    config_vf ns0 $VF $REP $IP
    ifconfig $NIC $LOCAL_TUN/24 up
    config_remote

    echo "add ct rules"
    tc filter add dev $NIC ingress protocol ip prio 2 flower $tc_verbose \
        dst_mac $NIC_MAC ct_state -trk action ct action goto chain 1
    verify_in_hw $NIC 2

    tc filter add dev $NIC ingress protocol ip chain 1 prio 3 flower $tc_verbose \
        dst_mac $NIC_MAC ct_state +trk+new action mirred egress redirect dev $REP
    verify_in_hw $NIC 3

    fail_if_err

    echo $NIC
    tc filter show dev $NIC ingress

    t=6
    echo "sniff packets on $VF"
    timeout $t ip netns exec ns0 tcpdump -qnnei $VF -c 30 udp  &>/dev/null &
    pid1=$!
    echo

    echo "sniff packets on $NIC"
    timeout $t tcpdump -qnnei $NIC -c 30 udp &
    pid2=$!

    sleep 1
    echo "run traffic for $t seconds"
    on_remote ping -q -i 0.1 -c 30 -W0.1 $IP
    # ping expected to fail we just test one direction and dont reply

    title "verify traffic on $REP"
    verify_have_traffic $pid1
    title "verify no traffic on $NIC"
    verify_no_traffic $pid2

    reset_tc $NIC
}


start_check_syndrome
run
check_syndrome
test_done
