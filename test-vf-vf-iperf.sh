#!/bin/bash
#
# 
#

NIC=${1:-ens5f0}
VF=${2:-ens5f2}
REP=${4:-ens5f0_0}
my_dir="$(dirname "$0")"
. $my_dir/common.sh

test -z "$VF2" && fail "Missing VF2"
test -z "$REP2" && fail "Missing REP2"

IP1="7.7.7.1"
IP2="7.7.7.2"

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

function check_bw() {
    SUM=`cat $TMPFILE | grep ",-1,0.0-10.0," | tail -n1`
    BW=${SUM##*,}

    test -z "$SUM" && err "Missing sum line" && return
    test -z "$BW" && err "Missing bw" && return

    let MIN_EXPECTED=9*1024*1024*1024

    if (( $BW < $MIN_EXPECTED )); then
        err "Expected BW $BW > $MIN_EXPECTED"
    else
        success
    fi
}

function test_tcp() {
    title "Test iperf tcp $VF($IP1) -> $VF2($IP2)"
    TMPFILE=/tmp/iperf.log
    ip netns exec ns0 iperf -s &
    ip netns exec ns1 iperf -c $IP1 -i 5 -t 10 -y c -b1G -P10 > $TMPFILE
    killall iperf
}

function test_udp() {
    title "Test iperf udp $VF($IP1) -> $VF2($IP2)"
    TMPFILE=/tmp/iperf.log
    ip netns exec ns0 iperf -u -s &
    ip netns exec ns1 iperf -u -c $IP1 -i 5 -t 10 -y c -b1G -P10 > $TMPFILE
    killall iperf
}

test_tcp
check_bw

test_udp
check_bw

del_all_bridges
cleanup
if [ $MULTIPATH == 1 ]; then
    disable_sriov
    disable_multipath
fi
test_done
