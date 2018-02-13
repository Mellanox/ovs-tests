#!/bin/bash
#
# Bug SW #1040416: slow path xmit on VF reps broken
#
# with tcpdump we could see traffic VF->rep works but rep->VF doesn't.
#
# Bug SW #1242030: [ASAP MLNX OFED] VF to Rep traffic doesn't work after
# reconfiguring VFs without reloading mlx5_core
#
# Bug SW #1244300: Crash reconfiguring SRIOV+switchdev more than once with
# different VFs per port
#

NIC=${1:-ens5f0}
VF=${2:-ens5f2}
REP=${3:-ens5f0_0}
my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_multipath_support

IP1="7.7.7.1"
IP2="7.7.7.2"

function disable_sriov() {
    title "- Disable SRIOV"
    echo 0 > /sys/class/net/$NIC/device/sriov_numvfs
    echo 0 > /sys/class/net/$NIC2/device/sriov_numvfs
}

function enable_sriov() {
    title "- Enable SRIOV"
    echo $VF_COUNT_PF0 > /sys/class/net/$NIC/device/sriov_numvfs
    echo $VF_COUNT_PF1 > /sys/class/net/$NIC2/device/sriov_numvfs
}

function cleanup() {
    ip netns del ns0 2> /dev/null
    ifconfig $REP 0
}

function ping_test() {
    cleanup
    ifconfig $REP $IP1/24 up
    ip netns add ns0
    ip link set $VF netns ns0
    ip netns exec ns0 ifconfig $VF $IP2/24 up

    title "Test ping REP($IP1) -> VF($IP2)"
    ping -q -c 10 -i 0.2 -w 2 $IP2 && success || err

    title "Test ping VF($IP2) -> REP($IP1)"
    ip netns exec ns0 ping -q -c 10 -i 0.2 -w 2 $IP1 && success || err
}

function do_test() {
    disable_sriov
    title "- Enable multipath"
    disable_multipath
    enable_multipath || err "Failed to enable multipath"
    enable_sriov
    set_macs
    enable_switchdev $NIC
    enable_switchdev $NIC2
    bind_vfs
    sleep 2
    ping_test || err
}


VF_COUNT_PF0=2
VF_COUNT_PF1=1
for i in `seq 2`; do
    do_test || break
    cleanup
done

disable_sriov
disable_multipath
test_done
