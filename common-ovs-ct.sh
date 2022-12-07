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
    local have_traffic=$1
    local no_traffic=$2

    if [ "$have_traffic" == "" ] && [ "$no_traffic" == "" ]; then
        err "Nothing to verify"
        return
    fi

    local nic
    declare -A tpids
    local tcpdump_timeout=$((t-4))

    for nic in $have_traffic; do
        echo "start sniff on $nic"
        if [ -e /sys/class/net/$nic ]; then
            timeout $tcpdump_timeout tcpdump -qnnei $nic -c 30 tcp &
        else
            ip netns exec ns0 timeout $tcpdump_timeout tcpdump -qnnei $nic -c 30 tcp &
        fi
        tpids[$nic]=$!
    done

    for nic in $no_traffic; do
        echo "start sniff on $nic"
        timeout $tcpdump_timeout tcpdump -qnnei $nic -c 10 tcp &
        tpids[$nic]=$!
    done

    sleep $t

    for nic in $have_traffic; do
        title "Verify traffic on $nic"
        verify_have_traffic ${tpids[$nic]}
    done

    for nic in $no_traffic; do
        title "Verify offload on $nic"
        verify_no_traffic ${tpids[$nic]}
    done
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

function verify_ct_hw_counter() {
    local sysfs_counter="/sys/kernel/debug/mlx5/$PCI/ct/offloaded"
    local cnt=$1
    local a
    log "checking hw offload ct tuples count is at least $cnt"

    if [ -f $sysfs_counter ]; then
        a=`cat $sysfs_counter`
    else
        a=`cat /proc/net/nf_conntrack | grep HW_OFFLOAD | wc -l`
        a=$((a*2))
    fi

    echo "offloaded ct tuples count: $a"
    if [ $a -lt $cnt ]; then
        err "low count, expected at least $cnt"
    fi
}
