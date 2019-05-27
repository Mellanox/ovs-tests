#!/bin/bash
#
# Test eswitch ingress rate limit
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

enable_switchdev_if_no_rep $REP

VFIP=10.0.0.1
BRIP=10.0.0.2
OVSBR=mybr

# rates in mbps.
rates="1 2 3 4"

function cleanup() {
    start_clean_openvswitch &>/dev/null
    ip netns del ns0 &>/dev/null
    stop_iperf
}
trap cleanup EXIT

function stop_iperf() {
    killall iperf &>/dev/null
    killall iperf &>/dev/null
    wait &>/dev/null
}

function config() {
    cleanup
    bind_vfs
    ovs-vsctl add-br $OVSBR
    ovs-vsctl add-port $OVSBR $REP
    ip link set up dev $REP
    ip netns add ns0
    ip link set dev $VF netns ns0
    ip netns exec ns0 ip link set up dev $VF
    ip netns exec ns0 ip addr add $VFIP/24 dev $VF
    ip link set up dev $OVSBR
    ip addr add $BRIP/24 dev $OVSBR
}

function run_test() {
    iperf -s -fm &

    for rate in $rates; do
        let rate1=rate*1000

        title "Test eswitch ingress rate $rate1"

        ovs-vsctl set interface $REP ingress_policing_rate=$rate1

        mrate=$(ip netns exec ns0 iperf -t 30 -fm -c $BRIP | grep "Mbits/sec" | sed -e 's/Mbits\/sec//' | gawk '{printf $NF}')
        if [ -z "$mrate" ]; then
            err "Couldn't get iperf rate"
            continue
        fi
        mrate=$(bc <<< "$mrate * 1000" | sed -e 's/\..*//')

        upper=$(bc <<< "$rate * 1100")
        lower=$(bc <<< "$rate * 900")

        if (( mrate < lower || mrate > upper )); then
            err "Measured rate $mrate out of range [$lower, $upper]"
        else
            success "Measured rate $mrate is in range [$lower, $upper]"
        fi

        # WORKAROUND. BUG in OVS when changing rate limit again so clean through tc.
        tc chain delete dev $REP root matchall
    done

    stop_iperf
}

config
run_test
cleanup
test_done
