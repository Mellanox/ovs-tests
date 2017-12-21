#!/bin/bash
#
# 
#

NIC=${1:-ens5f0}
VF=${2:-ens5f2}
REP=${3:-ens5f0_0}
REP2=${3:-ens5f0_1}
my_dir="$(dirname "$0")"
. $my_dir/common.sh

IP1="7.7.7.1"
IP2="7.7.7.2"

enable_switchdev_if_no_rep $REP
bind_vfs

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
    ifconfig $rep 0
    ip netns add $ns
    ip link set $vf netns $ns
    ip netns exec $ns ifconfig $vf $ip/24 up
}


cleanup
start_clean_openvswitch
config_vf ns0 $VF $REP $IP1
config_vf ns1 $VF2 $REP2 $IP2
BR=ov1
ovs-vsctl add-br $BR
ovs-vsctl add-port $BR $REP
ovs-vsctl add-port $BR $REP2

title "Test ping VF($IP1) -> VF($IP2)"
ip netns exec ns0 ping -q -c 10 -i 0.2 -w 2 $IP2 && success || err

del_all_bridges
cleanup
test_done
