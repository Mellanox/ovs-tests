function ping_remote() {
    ip netns exec ns0 ping -q -c 1 -w 2 $REMOTE
    if [ $? -ne 0 ]; then
        err "ping failed"
        return 1
    fi
    return 0
}

function initial_traffic() {
    title "Initial traffic"
    # this part is important when using multi-table CT.
    # the initial traffic will cause ovs to create initial tc rules
    # and also tuple rules. but since ovs adds the rules somewhat late
    # conntrack will already mark the conn est. and tuple rules will be in hw.
    # so we start second traffic which will be faster added to hw before
    # conntrack and this will check the miss rule in our driver is ok
    # (i.e. restoring reg_0 correctly)
    ip netns exec ns0 iperf3 -s -D
    on_remote timeout -k1 3 iperf3 -c $IP -t 2
    killall -9 iperf3
}

function start_traffic() {
    title "Start traffic"
    t=16
    on_remote iperf3 -s -D
    ip netns exec ns0 timeout -k1 $((t+2)) iperf3 -c $REMOTE -t $t -P3 &
    pid2=$!

    # verify pid
    sleep 4
    kill -0 $pid2 &>/dev/null
    if [ $? -ne 0 ]; then
        on_remote killall -9 -q iperf3
        err "iperf failed"
        return 1
    fi
    return 0
}

function verify_traffic() {
    ip netns exec ns0 timeout $((t-4)) tcpdump -qnnei $VF -c 30 tcp &
    tpid1=$!
    timeout $((t-4)) tcpdump -qnnei $REP -c 10 tcp &
    tpid2=$!
    if [ -n "$vxlan_dev" ]; then
        timeout $((t-4)) tcpdump -qnnei $vxlan_dev -c 10 tcp &
        tpid3=$!
    fi

    sleep $t
    title "Verify traffic on $VF"
    verify_have_traffic $tpid1
    title "Verify offload on $REP"
    verify_no_traffic $tpid2
    if [ -n "$vxlan_dev" ]; then
        title "Verify offload on $vxlan_dev"
        verify_no_traffic $tpid3
    fi
}

function kill_traffic() {
    killall -9 -q iperf3
    on_remote killall -9 -q iperf3
    echo "wait for bgs"
    wait &>/dev/null
}

function verify_ct_udp_have_traffic() {
    local pid1=$1
    local pid2=$2

    title "Verify traffic"
    verify_have_traffic $pid1
    if [[ -n $pid2 ]]; then
        verify_have_traffic $pid2
    fi
    # short-lived udp connections are not offloaded so wait a bit for offload.
    sleep 3
}
