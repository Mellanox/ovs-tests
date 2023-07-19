#!/bin/bash
#
# Test eswitch ingress rate limit
#
# BUG SW #2790606: [upstream] test-eswitch-ingress-rate-limit.sh: ERROR: Got 0 stats for ip filter
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

config_sriov 2
enable_switchdev
require_interfaces REP REP2
bind_vfs
reset_tc $REP $REP2

IP1=10.0.0.1
IP2=10.0.0.2
OVSBR=br-ovs

# rates in mbps.
rates="16 32"

function cleanup() {
    stop_iperf
    start_clean_openvswitch &>/dev/null
    ip netns del ns0 &>/dev/null
}
trap cleanup EXIT

function stop_iperf() {
    killall -q -9 iperf3 &>/dev/null
    wait &>/dev/null
}

function config() {
    cleanup
    ovs-vsctl add-br $OVSBR
    ovs-vsctl add-port $OVSBR $REP
    ovs-vsctl add-port $OVSBR $REP2
    config_vf ns0 $VF $REP $IP1
    ip link set up dev $REP2
}

function config_dev() {
    local dev=$1
    ip link set up dev $dev
    ip addr add $IP2/24 dev $dev

    # After moving to switchdev mode rate limiting doesn't work for first couple
    # of seconds of traffic. Previous test version just ignored first second of
    # every session of iperf3 in total rate calculation. However, 1 second is
    # not enough to stabilize the rate on newer NICs like cx6dx. Instead of
    # trying to guess exact timeout to ignore with iperf3 'O' flag just execute
    # single warm-up iperf3 run when configuring the device.
    ovs-vsctl set interface $REP ingress_policing_rate=10000
    ip netns exec ns0 iperf3 -t 10 -fm -c $IP2
}

function check_mrate() {
    local rate=$1
    local mrate=$(ip netns exec ns0 iperf3 -t 15 -fm -c $IP2 -O 1 | grep 'sender' | gawk '{printf $7}')

    tc -s filter show dev $REP ingress protocol ip | grep -q "Sent 0"
    if [ $? -eq 0 ]; then
        tc -s filter show dev $REP ingress protocol ip
        err "Got 0 stats"
        return
    fi

    if [ -z "$mrate" ]; then
        err "Couldn't get iperf rate"
        return
    fi

    mrate=$(bc <<< "$mrate * 1000" | sed -e 's/\..*//')

    local upper=$(bc <<< "$rate * 1100")
    local lower=$(bc <<< "$rate * 900")

    if (( mrate < lower || mrate > upper )); then
        err "Measured rate $mrate out of range [$lower, $upper]"
    else
        success "Measured rate $mrate is in range [$lower, $upper]"
    fi
}

function run_rates() {
    for rate in $rates; do
        let rate1=rate*1000

        title "Test eswitch ingress rate $rate1"

        ovs-vsctl set interface $REP ingress_policing_rate=$rate1
        if ! tc -oneline filter show dev $REP ingress | grep -w in_hw | grep "rate ${rate}Mbit" > /dev/null; then
            err "Matchall filter not in hardware"
            continue
        fi

        check_mrate $rate
    done
}

function run() {
    local dev=$1

    config_dev $dev
    for pf_state in down up; do
        title "pf link $pf_state"
        ip link set $NIC $pf_state
        run_rates
    done
    ip addr flush dev $dev
    ip netns exec ns0 arp -d $IP2
}


config

iperf3 -s -fm -D
sleep 1

# Newer NICs support internal port offload, which will cause VF->BR rule to be
# in_hw. Since using internal port in such way is not intended by internal port
# implementation, is not tested in internal port-dedicated tests and doesn't
# work when uplink link is down anyway, just don't execute this part of the
# test.
if [ "$short_device_name" == "cx5" ]; then
    title "Test VF->BR"
    run $OVSBR
fi

title "Test VF->VF"
run $VF2

cleanup
test_done
