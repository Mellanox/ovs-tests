#!/bin/bash
#
# Test tc trap
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


function cleanup() {
    ip netns del ns0 2>/dev/null
    ip netns del ns1 2>/dev/null
    reset_tc $REP $REP2
}
trap cleanup EXIT

function config() {
    config_sriov 2
    log "set switchdev"
    enable_switchdev
    bind_vfs
    require_interfaces REP REP2 VF1 VF2
    cleanup

    log "config network"
    mac0=`cat /sys/class/net/$VF1/address`
    mac1=`cat /sys/class/net/$VF2/address`
    ip link set up dev $REP
    ip link set up dev $REP2

    ip netns add ns0
    ip netns add ns1
    ip link set netns ns0 dev $VF1
    ip link set netns ns1 dev $VF2

    ip netns exec ns0 ip link set up dev $VF1
    ip netns exec ns0 ip addr add 7.7.7.7/24 dev $VF1
    ip netns exec ns1 ip link set up dev $VF2
    ip netns exec ns1 ip addr add 7.7.7.8/24 dev $VF2
    ip netns exec ns0 ip neigh add 7.7.7.8 lladdr $mac1 dev $VF1
    ip netns exec ns1 ip neigh add 7.7.7.7 lladdr $mac0 dev $VF2

    title "add tc rules"
    reset_tc $REP $REP2
    tc_filter add dev $REP protocol all prio 4 root flower dst_mac $mac1 action mirred egress redirect dev $REP2
    tc_filter add dev $REP2 protocol all prio 4 root flower dst_mac $mac0 action mirred egress redirect dev $REP
}

function test_trap() {
    title "Test tc trap rule"
    config

    rm -f /tmp/_xx
    timeout 4 tcpdump -ni $REP src 7.7.7.7 -w /tmp/_xx &
    local pid=$!
    sleep 1
    ip netns exec ns1 ping -c 3 -w 4 7.7.7.7 || fail "Ping failed"
    wait $pid
    sync

    n=$(tcpdump -nnr /tmp/_xx icmp | grep -c "ICMP echo reply")
    if (( n == 0 )); then
        success "ping offloaded"
    else
        err "ping not offloaded. $n packets."
    fi

    title "add trap action"
    tc_filter add dev $REP protocol ip prio 1 root flower skip_sw src_ip 7.7.7.7 action trap

    rm -f /tmp/_xx
    timeout 5 tcpdump -nni $REP src 7.7.7.7 -w /tmp/_xx &
    pid=$!
    sleep 1
    ip netns exec ns1 ping -c 3 -w 4 7.7.7.7
    wait $pid
    sync

    n=$(tcpdump -nnr /tmp/_xx icmp | grep -c "ICMP echo reply")
    if (( n == 3 )); then
        success "ping not offloaded, trap rule worked."
    else
        err "ping offloaded, trap rule didn't work. $n packets."
    fi

    rm -f /tmp/_xx
}


test_trap
trap - EXIT
cleanup
test_done
