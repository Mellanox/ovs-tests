#!/bin/bash
#
# Test OVS rules with vxlan traffic and vlan over VF, with vxlan pop + vlan push on RX
#
# Feature Request #2703197: [Design] - [ASAP^2] Support VLAN push on Rx and pop on TX on ConnectX-6dx

my_dir="$(dirname "$0")"
. $my_dir/common.sh

not_relevant_for_nic cx4 cx4lx cx5 cx6 cx6lx
require_remote_server

IP=1.1.1.7
REMOTE=1.1.1.8
LOCAL_TUN=7.7.7.7
REMOTE_IP=7.7.7.8
VXLAN_ID=42
vlan=20
vlandev=${VF}.$vlan

config_sriov 2
enable_switchdev
require_interfaces REP NIC
unbind_vfs
bind_vfs

function cleanup() {
    cleanup_remote_vxlan
    ip netns del ns0 &>/dev/null
    ip netns del ns1 &>/dev/null
    ip a flush dev $NIC
}
trap cleanup EXIT

function config() {
    ip a add $LOCAL_TUN/24 dev $NIC
    ip link set up dev $NIC

    ip netns add ns0
    ip link set dev $VF netns ns0
    ip netns exec ns0 ifconfig $VF up
    ip netns exec ns0  ip link add link $VF name $vlandev type vlan id $vlan
    ip netns exec ns0 ifconfig $vlandev $IP/24 up

    echo "Restarting OVS"
    start_clean_openvswitch

    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs vxlan1 -- set interface vxlan1 type=vxlan options:local_ip=$LOCAL_TUN options:remote_ip=$REMOTE_IP options:key=$VXLAN_ID options:dst_port=4789
    ovs-ofctl add-flow br-ovs "in_port=vxlan1,  action=push_vlan:0x8100,mod_vlan_vid:$vlan,$REP" -O OpenFlow11
    ovs-ofctl add-flow br-ovs "in_port=$REP,  action=pop_vlan,vxlan1"

    remote_disable_sriov
    config_remote_vxlan
}

function run_server() {
    on_remote timeout $((t+3)) iperf3 -D -s
}

function run_client() {
    ip netns exec ns0 timeout $((t+2)) iperf3 -c $REMOTE -t $t -P3 -i2 &
    local pk2=$!

    # verify pid
    sleep 2
    kill -0 $pk2 &>/dev/null
    [ $? -eq 0 ] || err "iperf3 client failed"

}

function kill_traffic() {
    killall -q iperf3
    on_remote "killall -q iperf3"
}

function run() {
    cleanup
    config
    sleep 1

    ip netns exec ns0 ping -q -c 1 -i 0.1 -w 2 $REMOTE
    if [ $? -ne 0 ]; then
        err "ping failed"
        return
    fi

    t=10
    run_server
    run_client
    sleep 2

    local vx=vxlan_sys_4789 rep_rules vx_rules
    rep_rules=$(tc filter show dev $REP ingress)
    vx_rules=$(tc filter show dev $vx ingress)

    sleep $t
    kill_traffic

    title " - show $REP rules"
    echo "$rep_rules"
    grep -qw "^\s*not_in_hw" <<<"$rep_rules" && err "Some rule is not in hw on $REP"
    grep -qw in_hw <<<"$rep_rules" || err "No in_hw TC rules found on $REP"

    title " - show $vx rules"
    echo "$vx_rules"
    grep -qw "^\s*not_in_hw" <<<"$vx_rules" && err "Some rule is not in hw on $vx"
    grep -qw in_hw <<<"$vx_rules" || err "No in_hw TC rules found on $vx"

    start_clean_openvswitch
}

title "Test OVS RX with vxlan pop + vlan push"
run

trap - EXIT
cleanup
test_done
