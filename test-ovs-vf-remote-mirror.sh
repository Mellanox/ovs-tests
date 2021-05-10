#!/bin/bash
#
# Test remote mirror over vxlan:
#   Two tunnels are created, ping remote host over on tunnel, and the
#   mirrored packets are sent back over the other tunnel.
#   To pass this test, no icmp packets can be captured on REP, while
#   mirrored ones are captured on VF2.
#
# Bug SW #2626920: CX6 - vxlan headers are sent to VM
#
# Note that the test assumes that NIC and REP have same names on local and remote hosts
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_remote_server

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

VXLAN_ID1=42
VXLAN_ID2=52

function cleanup_remote() {
    on_remote "ip a flush dev $NIC; \
               ip netns del ns0 &>/dev/null"
}

function cleanup() {
    ip a flush dev $NIC
    ip netns del ns0 &>/dev/null
    ip netns del ns1 &>/dev/null
    cleanup_remote
    sleep 0.5
}
trap cleanup EXIT

function prep_setup()
{
    local remote=$1

    local cmd="config_sriov 2; \
               enable_switchdev; \
               unbind_vfs; \
               bind_vfs; \
               start_clean_openvswitch; \
               start_check_syndrome; \
               reset_tc $NIC $REP $REP2; "

    if [ "X$remote" != "X" ]; then
        title "Prep remote"
        on_remote_dt "$cmd"
    else
        title "Prep local"
        eval "$cmd"
    fi
    [ $? -eq 0 ] || fail "Preparing setup failed!"
}

function setup_topo()
{
    local tundev=$1; shift
    local vf=$1; shift
    local rep=$1; shift
    local tunip=$1; shift
    local vfip=$1; shift
    local vfdest=$1; shift
    local tundest=$1; shift
    local remote=$1; shift

    if [ "X$remote" != "X" ]; then
        mac="00:00:00:00:03:02"
    else
        mac="00:00:00:00:03:01"
    fi

    local cmd="config_vf ns0 $vf $rep $vfip $mac; \
               ip link set dev $tundev up; \
               ip addr add $tunip/24 dev $tundev; \
               ovs-vsctl add-br br-ovs; \
               ovs-vsctl add-port br-ovs $rep; \
               ovs-vsctl add-port br-ovs vxlan1 -- set interface vxlan1 type=vxlan \
                   options:local_ip=$tunip options:remote_ip=$tundest \
                   options:key=$VXLAN_ID1 options:dst_port=4789; "

    if [ "X$remote" != "X" ]; then
        extra_cmd="ovs-vsctl add-port br-ovs vxlan2 -- set interface vxlan2 type=vxlan \
                       options:local_ip=$tunip options:remote_ip=$tundest \
                       options:key=$VXLAN_ID2 options:dst_port=4789; \
                   ovs-vsctl -- --id=@p1 get port $rep -- --id=@p2 get port vxlan2 -- \
                       --id=@m create mirror name=m1 select_src_port=@p1 select_dst_port=@p1 \
                       output-port=@p2 -- set bridge br-ovs mirrors=@m; "

        title "Setup topo on remote"
        on_remote_dt "$cmd$extra_cmd"
    else
        extra_cmd="ovs-vsctl add-br br-ovs-m; \
                   config_vf ns1 $VF2 $REP2 3.3.3.3 00:00:00:00:03:03; \
                   ovs-vsctl add-port br-ovs-m $REP2; \
                   ovs-vsctl add-port br-ovs-m vxlan2 -- set interface vxlan2 type=vxlan \
                       options:local_ip=$tunip options:remote_ip=$tundest \
                       options:key=$VXLAN_ID2 options:dst_port=4789; \
                   ovs-ofctl add-flow br-ovs-m \"in_port=vxlan2,action=$REP2\"; "

        title "Setup topo on local"
        eval "$cmd$extra_cmd"
    fi

    [ $? -eq 0 ] || fail "Preparing test topo failed!"
}

cleanup
remote_disable_sriov
disable_sriov
wait_for_ifaces

prep_setup
prep_setup "remote"

require_interfaces NIC VF REP VF2 REP2
on_remote_dt "require_interfaces NIC VF REP"

setup_topo "$NIC" "$VF" "$REP" "$tunip1" "$vfip1" "$vfdest1" "$tundest1"
setup_topo "$NIC" "$VF" "$REP" "$tunip2" "$vfip2" "$vfdest2" "$tundest2" "remote"

ip netns exec ns0 ping -q -c 2 -w 2 $vfip2 || err

echo "Try to capture remote packets on $VF2"
timeout 5 ip netns exec ns1 tcpdump -qnnei $VF2 -c 4 icmp &
tpid_1=$!

echo "Try to capture packets on $REP"
timeout 6 tcpdump -qnnei $REP -c 4 icmp &
tpid_2=$!

title "Test ping local $VF($vfip1) -> remote $VF($vfip2)"
ip netns exec ns0 ping -q -f -w 4 $vfip2 && success || err

echo "verify tcpdump on $VF2"
verify_have_traffic $tpid_1

echo "verify tcpdump on $REP"
verify_no_traffic $tpid_2

cleanup
check_syndrome

test_done
