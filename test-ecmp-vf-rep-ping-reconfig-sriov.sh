#!/bin/bash
#
# Bug SW #1040416: slow path xmit on VF reps broken
#
# with tcpdump we could see traffic VF->rep works but rep->VF doesn't.
#
# Bug SW #1242030: [ASAP MLNX OFED] VF to Rep traffic doesn't work after
# reconfiguring VFs without reloading mlx5_core
#
# Bug SW #1244300: system crash after reconfig SRIOV several time
#

NIC=${1:-ens5f0}
VF=${2:-ens5f2}
REP=${3:-ens5f0_0}
my_dir="$(dirname "$0")"
. $my_dir/common.sh


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

function do_test() {
    disable_sriov
    title "- Enable multipath"
    disable_multipath
    enable_multipath || err "Failed to enable multipath"
    enable_sriov
    enable_switchdev $NIC
    enable_switchdev $NIC2
    $my_dir/test-vf-rep-ping-reconfig-sriov.sh || err
}


for i in `seq 10`; do
    do_test || break
done

disable_sriov
disable_multipath
test_done
