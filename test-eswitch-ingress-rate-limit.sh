#!/bin/bash
#
# Test eswitch ingress rate limit
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

enable_switchdev
require_interfaces REP REP2
unbind_vfs
bind_vfs
reset_tc $REP $REP2

IP1=10.0.0.1
IP2=10.0.0.2
OVSBR=br-ovs

# rates in mbps.
rates="1 2 3 4"

function cleanup() {
    stop_iperf
    start_clean_openvswitch &>/dev/null
    ip netns del ns0 &>/dev/null
}
trap cleanup EXIT

function stop_iperf() {
    killall -q -9 iperf &>/dev/null
    wait &>/dev/null
}

function config() {
    cleanup
    ovs-vsctl add-br $OVSBR
    ovs-vsctl add-port $OVSBR $REP
    ovs-vsctl add-port $OVSBR $REP2
    config_vf ns0 $VF $REP $IP1
}

function config_dev() {
    local dev=$1
    ip link set up dev $dev
    ip addr add $IP2/24 dev $dev
}

function check_mrate() {
    local rate=$1
    local mrate=$(ip netns exec ns0 iperf -t 10 -fm -c $IP2 | grep "Mbits/sec" | sed -e 's/Mbits\/sec//' | gawk '{printf $NF}')

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
}


config

iperf -s -fm &
sleep 1

title "Test VF->BR"
run $OVSBR

title "Test VF->VF"
run $VF2

cleanup
test_done
