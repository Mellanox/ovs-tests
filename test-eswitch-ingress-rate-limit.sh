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
rates="8 12"

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
}

function config_dev() {
    local dev=$1
    ip link set up dev $dev
    ip addr add $IP2/24 dev $dev
}

function check_mrate() {
    local rate=$1
    local mrate=$(ip netns exec ns0 iperf3 -t 15 -fm -c $IP2 -O 1 | grep 'sender' | gawk '{printf $7}')

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

title "Test VF->BR"
run $OVSBR

title "Test VF->VF"
run $VF2

cleanup
test_done
