#!/bin/bash
#
# Test CT with unidirectional traffic
# Feature #2829954: CX5 ASAP2 Kernel: Need offload UDP uni-directional traffic under CT
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module act_ct

IP1="7.7.7.1"
IP2="7.7.7.2"

config_sriov
enable_switchdev
require_interfaces REP REP2
unbind_vfs
bind_vfs
reset_tc $REP
reset_tc $REP2

mac1=`cat /sys/class/net/$VF/address`
mac2=`cat /sys/class/net/$VF2/address`

test "$mac1" || fail "no mac1"
test "$mac2" || fail "no mac2"

function cleanup() {
    ip netns del ns0 2> /dev/null
    ip netns del ns1 2> /dev/null
    reset_tc $REP
    reset_tc $REP2
}
trap cleanup EXIT

function randport() {
    echo $((RANDOM%60000 + 1000))
}

sport=`randport`
dport=`randport`

function run_python_ns() {
    local ns=$1; shift;

    #echo "[$ns] python: $@"
    ip netns exec $ns python -c "$@"
}

function wait_for_enter() {
    while [ true ]; do
        if read -t 30 -p "Hit any key to continue" -n 1
        then
            break;
        fi
    done
}

function verify_mf_in_hw() {
    expected=$1
    in_hw_num=`cat /sys/class/net/enp8s0f0/device/sriov/pf/counters_tc_ct | grep "currently_in_hw" | grep -o -E ": ([0-9]+)"  | cut -d' ' -f2`
    if [[ $in_hw_num -ne $expected ]]; then
        err "Expected currently_in_hw should be $expected but got $in_hw_num"
    fi
}

# ns_send_pkt ns src dst sport dport data
function ns_send_pkt() {
    ns=$1
    src=$2
    dst=$3
    s_port=$4
    d_port=$5
    data=$6
    run_python_ns $ns "from scapy.all import *; send(IP(src=\"$src\",dst=\"$dst\")/UDP(sport=$s_port,dport=$d_port)/\"$data\", verbose=0)"
}

function run() {
    title "Test CT unidirectional traffic offload"
    tc_test_verbose
    config_vf ns0 $VF $REP $IP1
    config_vf ns1 $VF2 $REP2 $IP2

    echo "add arp rules"
    tc_filter add dev $REP ingress protocol arp prio 1 flower $tc_verbose \
        action mirred egress redirect dev $REP2

    tc_filter add dev $REP2 ingress protocol arp prio 1 flower $tc_verbose \
        action mirred egress redirect dev $REP

    echo "add ct rules"
    tc_filter add dev $REP ingress protocol ip prio 2 flower $tc_verbose \
        dst_mac $mac2 ct_state -trk \
        action ct action goto chain 1

    tc_filter add dev $REP ingress protocol ip chain 1 prio 2 flower $tc_verbose \
        dst_mac $mac2 ct_state +trk+new \
        action ct commit \
        action mirred egress redirect dev $REP2

    tc_filter add dev $REP ingress protocol ip chain 1 prio 2 flower $tc_verbose \
        dst_mac $mac2 ct_state +trk+est \
        action mirred egress redirect dev $REP2

    # chain0,ct -> chain1,fwd
    tc_filter add dev $REP2 ingress protocol ip prio 2 flower $tc_verbose \
        dst_mac $mac1 \
        action ct action goto chain 1

    tc_filter add dev $REP2 ingress protocol ip prio 2 chain 1 flower $tc_verbose \
        dst_mac $mac1 ct_state +trk+est \
        action mirred egress redirect dev $REP

    fail_if_err

    echo $REP
    tc filter show dev $REP ingress
    echo $REP2
    tc filter show dev $REP2 ingress


    verify_mf_in_hw 0
    #------------------ DATA --->  --------------------
    echo "packet, orig 1"
    ns_send_pkt ns0 $IP1 $IP2 $sport $dport "A1"
    verify_mf_in_hw 1
    echo "packet, orig 2"
    ns_send_pkt ns0 $IP1 $IP2 $sport $dport "A2"
    verify_mf_in_hw 1
    echo "packet, orig 3"
    ns_send_pkt ns0 $IP1 $IP2 $sport $dport "A3"
    verify_mf_in_hw 1

    #------------------ DATA <---  --------------------

    echo "packet, reply"
    ns_send_pkt ns1 $IP2 $IP1 $dport $sport "B1"
    verify_mf_in_hw 2
    t=2
    echo "Waiting $t seconds for 'new' state flow to be aged out"
    sleep $t
    verify_mf_in_hw 1

    echo "packet, reply"
    ns_send_pkt ns1 $IP2 $IP1 $dport $sport "B2"
    verify_mf_in_hw 1

    #------------------ DATA --->  --------------------

    echo "packet, orig"
    ns_send_pkt ns0 $IP1 $IP2 $sport $dport "C1"
    verify_mf_in_hw 2
    echo "packet, orig"
    ns_send_pkt ns0 $IP1 $IP2 $sport $dport "C2"
    verify_mf_in_hw 2

    #------------------ DATA <---  --------------------

    echo "packet, reply"
    ns_send_pkt ns1 $IP2 $IP1 $dport $sport "D1"
    verify_mf_in_hw 2
    echo "packet, reply"
    ns_send_pkt ns1 $IP2 $IP1 $dport $sport "D2"
    verify_mf_in_hw 2

    reset_tc $REP $REP2
    # wait for traces as merging & offloading is done in workqueue.
    sleep 3
}


run
test_done
