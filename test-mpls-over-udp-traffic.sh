#!/bin/bash
# ex:ts=4:sw=4:sts=4:et
#
# Test MPLS over UDP traffic
#
# Bug SW #2576950: traffic of MPLS Over UDP is broken in v5.12
#
#
# Note that the test assumes that NIC and REP have same names on local and remote hosts
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_mlxconfig
require_remote_server

LABEL=555 # use whatever you want
UDPPORT=6635 # reserved UDP port

# local
tunip1=8.8.8.21
vfip1=2.2.2.21
tundest1=8.8.8.22
vfdest1=2.2.2.22

# remote
tunip2=8.8.8.22
vfip2=2.2.2.22
tundest2=8.8.8.21
vfdest2=2.2.2.21

function cleanup1() {
    [ -e /sys/class/net/bareudp0 ] && ip link del dev bareudp0
    for i in $NIC $REP $VF; do
        [ ! -e /sys/class/net/$i ] && continue
        reset_tc $i
        ip link set $i mtu 1500
        ifconfig $i 0
    done
}

function cleanup() {
    cleanup1
    on_remote_exec cleanup1
}
trap cleanup EXIT

function prep_setup1() {
    local profile=$1
    local remote=$2

    config_sriov 2
    enable_switchdev
    unbind_vfs
    bind_vfs
    start_clean_openvswitch
    reset_tc $NIC $REP
    ip link set dev $VF mtu 1468
    modprobe -av bareudp || fail "Can't load bareudp module"
}

function prep_setup() {
    local profile=$1
    local remote=$2

    if [ "X$remote" != "X" ]; then
        title "Prep remote profile $profile"
        on_remote_exec prep_setup1 "$@"
    else
        title "Prep local profile $profile"
        fw_config FLEX_PARSER_PROFILE_ENABLE=$profile || fail "Cannot set flex parser profile"
        fw_reset
        prep_setup1 "$@"
    fi
    [ $? -eq 0 ] || fail "Preparing setup failed!"
}

function setup_topo1() {
    local tundev=$1
    local vf=$2
    local rep=$3
    local tunip=$4
    local vfip=$5
    local vfdest=$6
    local tundest=$7
    local remote=$8
    local dstmac=$9
    local srcmac=$10
    local skip_hw=""

    if [ "$remote" == "remote" ]; then
        skip_hw="skip_hw"
    fi

    ip link add dev bareudp0 type bareudp dstport 6635 ethertype mpls_uc
    ip link set up dev bareudp0
    ip link set up dev $vf
    ip link set up dev $rep
    ip addr add $tunip/24 dev $tundev
    ip link set up dev $tundev
    ip addr add $vfip/24 dev $vf
    ip neigh add $vfdest lladdr 00:11:22:33:44:55 dev $vf

    tc filter add dev $rep protocol ip prio 1 root flower $skip_hw src_ip $vfip dst_ip $vfdest action tunnel_key set src_ip $tunip dst_ip $tundest  dst_port $UDPPORT tos 4 ttl 6 action mpls push protocol mpls_uc label $LABEL tc 3 action mirred egress redirect dev bareudp0
    tc qdisc add dev bareudp0 ingress
    tc filter add dev bareudp0 protocol mpls_uc prio 1 ingress flower $skip_hw enc_dst_port $UDPPORT mpls_label  $LABEL action mpls pop protocol ip pipe action vlan push_eth dst_mac $dstmac src_mac $srcmac pipe action mirred egress redirect dev $rep
}

function setup_topo() {
    local tundev=$1
    local vf=$2
    local rep=$3
    local tunip=$4
    local vfip=$5
    local vfdest=$6
    local tundest=$7
    local remote=$8

    if [ "X$remote" != "X" ]; then
        remote="on_remote"
    fi

    local dstmac=$(eval $remote ip link show dev $vf | grep ether | gawk '{print $2}')
    local srcmac=$(eval ip link show dev $vf | grep ether | gawk '{print $2}')

    if [ "X$remote" != "X" ]; then
        title "Setup topo on remote"
        on_remote "ethtool -K $REP hw-tc-offload off" && on_remote_exec setup_topo1 $@ $dstmac $srcmac
    else
        title "Setup topo on local"
        setup_topo1 $@ $dstmac $srcmac
    fi
    [ $? -eq 0 ] || fail "Preparing test topo failed!"
}

cleanup
remote_disable_sriov
disable_sriov
wait_for_ifaces

prep_setup 1
prep_setup 1 "remote"

require_interfaces NIC VF REP
on_remote_exec "require_interfaces NIC VF REP"

setup_topo "$NIC" "$VF" "$REP" "$tunip1" "$vfip1" "$vfdest1" "$tundest1"
setup_topo "$NIC" "$VF" "$REP" "$tunip2" "$vfip2" "$vfdest2" "$tundest2" "remote"

verify_in_hw bareudp0 1
verify_in_hw $REP 1

title "Test ping local $VF($vfip1) -> remote $VF($vfip2)"
ping -I $vfip1 $vfip2 -s 56 -f -nc 100 -w 1 && success || err "ping expected to pass"

title "Test iperf3"
iperf3 -s -1 -D &>/dev/null
on_remote timeout 10 iperf3 -c $vfip1 -t 5 || err "failed iperf3"
killall -9 iperf3 &>/dev/null

echo
title "=============       Local TC rules          =================="
title $REP
tc -s filter show dev $REP ingress
title "bareudp0"
tc -s filter show dev bareudp0 ingress

echo
title "=============       Remote TC rules         =================="
title $REP
on_remote tc -s filter show dev $REP ingress
title "bareudp0"
on_remote tc -s filter show dev bareudp0 ingress
echo

echo
title "=============           Cleanup             =================="
trap - EXIT
cleanup
prep_setup 0
prep_setup 0 "remote"

test_done
