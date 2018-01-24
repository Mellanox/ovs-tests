#!/bin/bash
#
# Test traffic while adding ofctl fwd and drop rules.
#
# Bug SW #1241076: [ECMP] Hit WARN_ON when adding many rules with different mask
#

NIC=${1:-ens2f0}
VF=${2:-ens2f2}
REP=${3:-eth0}
my_dir="$(dirname "$0")"
. $my_dir/common.sh

test -z "$VF2" && fail "Missing VF2"
test -z "$REP2" && fail "Missing REP2"

IP1="7.7.7.1"
IP2="7.7.7.2"

TIMEOUT=${TIMEOUT:-120}
ROUNDS=${ROUNDS:-10}
MULTIPATH=${MULTIPATH:-0}

function cleanup() {
    ip netns del ns0 2> /dev/null
    ip netns del ns1 2> /dev/null
}

function config_vf() {
    local ns=$1
    local vf=$2
    local rep=$3
    local ip=$4

    echo "$ns : $vf ($ip) -> $rep"
    if [ ! -e /sys/class/net/$vf ]; then
        err "Cannot find $vf"
        return 1
    fi
    if [ ! -e /sys/class/net/$rep ]; then
        err "Cannot find $rep"
        return 1
    fi
    ifconfig $rep 0 up
    ip netns add $ns
    ip link set $vf netns $ns
    ip netns exec $ns ifconfig $vf $ip/24 up
}

function disable_sriov() {
    title "- Disable SRIOV"
    echo 0 > /sys/class/net/$NIC/device/sriov_numvfs
    echo 0 > /sys/class/net/$NIC2/device/sriov_numvfs
}

function enable_sriov() {
    title "- Enable SRIOV"
    echo 2 > /sys/class/net/$NIC/device/sriov_numvfs
    echo 2 > /sys/class/net/$NIC2/device/sriov_numvfs
}


if [ $MULTIPATH == 1 ]; then
    disable_sriov
    enable_multipath || fail
    enable_sriov
    enable_switchdev $NIC
    enable_switchdev $NIC2
    bind_vfs $NIC
    bind_vfs $NIC2
else
    enable_switchdev_if_no_rep $REP
    bind_vfs
fi

cleanup
start_clean_openvswitch
config_vf ns0 $VF $REP $IP1
config_vf ns1 $VF2 $REP2 $IP2

BR=ov1
ovs-vsctl add-br $BR
ovs-vsctl add-port $BR $REP
ovs-vsctl add-port $BR $REP2

title "Test ping $VF($IP1) -> $VF2($IP2)"
ip netns exec ns0 ping -q -c 10 -i 0.2 -w 2 $IP2 && success || err

title "Test iperf $VF($IP1) -> $VF2($IP2)"
timeout $TIMEOUT ip netns exec ns1 iperf3 -s --one-off -i 0 || err &
sleep 1
timeout $TIMEOUT ip netns exec ns0 iperf3 -c $IP2 -t $((TIMEOUT-10)) -B $IP1 -P 100 --cport 6000 -i 0 || err &

ovs-ofctl add-flow $BR "dl_dst=11:11:11:11:11:11,actions=drop"

for r in `seq $ROUNDS`; do
    if [ $TEST_FAILED == 1 ]; then
        killall iperf3
        break
    fi
    title "- round $r/$ROUNDS"
    sleep 2
    title "- add fwd rules above 6000"
    for i in {6110..6500..1}; do
        ovs-ofctl add-flow $BR "in_port=$REP,tcp,tcp_src=$i,actions=output:$REP2" || err "adding ofctl rule"
    done
    sleep 2
    title "- add fwd rules from 6000"
    for i in {6000..6098..2}; do
        ovs-ofctl add-flow $BR "in_port=$REP,tcp,tcp_src=$i,actions=output:$REP2" || err "adding ofctl rule"
    done
    sleep 2
    title "- add drop rules"
    for i in {6000..6100..2}; do
        ovs-ofctl add-flow $BR "in_port=$REP,tcp,tcp_src=$i,actions=drop" || err "adding ofctl rule"
    done
    sleep 2
    title "- clear rules"
    ovs-ofctl del-flows $BR tcp
done

wait

del_all_bridges
cleanup
if [ $MULTIPATH == 1 ]; then
    disable_sriov
    disable_multipath
fi
test_done
