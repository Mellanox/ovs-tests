#!/bin/bash
#
# Test OVS CT with vxlan traffic
#
# Bug 1824795: [ASAP-BD, Connection tracking]: Traffic failed to be offloaded on recv side (different hosts) (wont fix)
# Bug SW #1827703: CT VXLAN traffic decap is not offloaded
#
# Uplink reps register to egdev_all
# last port registers will be on top
# on vxlan decap without egress action, like ct+goto chain,
# we will call egdev_all and the first on the list
# is the last port registered but we might run traffic
# on the first port. so miniflow->priv is incorrect.
#
# Only different from test-ovs-ct-vxlan-2.sh is order of ports
# we set to switchdev.
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module act_ct
require_remote_server

IP=1.1.1.7
REMOTE=1.1.1.8

LOCAL_TUN=7.7.7.7
REMOTE_IP=7.7.7.8
VXLAN_ID=42


function config_ports() {
    # config second port
    config_sriov 0 $NIC2
    config_sriov 1 $NIC2
    enable_switchdev $NIC2
    reset_tc $NIC2

    # config first port
    config_sriov 2
    enable_legacy
    enable_switchdev
    require_interfaces REP NIC
    unbind_vfs
    bind_vfs
}

function set_nf_liberal() {
    nf_liberal="/proc/sys/net/netfilter/nf_conntrack_tcp_be_liberal"
    if [ -e $nf_liberal ]; then
        echo 1 > $nf_liberal
        echo "`basename $nf_liberal` set to: `cat $nf_liberal`"
    else
        echo "Cannot find $nf_liberal"
    fi
}

function cleanup() {
    config_sriov 0 $NIC2
    ip a flush dev $NIC
    ip netns del ns0 &>/dev/null
    ip netns del ns1 &>/dev/null
    ovs_clear_bridges
    reset_tc $REP &>/dev/null
    cleanup_remote_vxlan
    sleep 0.5
}
trap cleanup EXIT

function config() {
    cleanup
    config_ports
    set_nf_liberal
    conntrack -F
    ifconfig $NIC $LOCAL_TUN/24 up
    # WA SimX bug? interface not receiving traffic from tap device to down&up to fix it.
    for i in $NIC $VF $REP ; do
            ifconfig $i down
            ifconfig $i up
            reset_tc $i
    done
    ip netns add ns0
    ip link set dev $VF netns ns0
    ip netns exec ns0 ifconfig $VF $IP/24 up

    echo "Restarting OVS"
    start_clean_openvswitch

    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs vxlan1 -- set interface vxlan1 type=vxlan options:local_ip=$LOCAL_TUN options:remote_ip=$REMOTE_IP options:key=$VXLAN_ID options:dst_port=4789
}

function add_openflow_rules() {
    ovs-ofctl del-flows br-ovs
    ovs-ofctl add-flow br-ovs arp,actions=normal
    ovs-ofctl add-flow br-ovs icmp,actions=normal
    ovs-ofctl add-flow br-ovs "table=0, tcp,ct_state=-trk actions=ct(table=1)"
    ovs-ofctl add-flow br-ovs "table=1, tcp,ct_state=+trk+new actions=ct(commit),normal"
    ovs-ofctl add-flow br-ovs "table=1, tcp,ct_state=+trk+est actions=normal"
    ovs-ofctl dump-flows br-ovs --color
}

function initial_traffic() {
    title "initial traffic"
    # this part is important when using multi-table CT.
    # the initial traffic will cause ovs to create initial tc rules
    # and also tuple rules. but since ovs adds the rules somewhat late
    # conntrack will already mark the conn est. and tuple rules will be in hw.
    # so we start second traffic which will be faster added to hw before
    # conntrack and this will check the miss rule in our driver is ok
    # (i.e. restoring reg_0 correctly)
    ip netns exec ns0 iperf3 -s -D
    on_remote timeout -k1 3 iperf3 -c $IP -t 2
    killall -9 iperf3
}

function run() {
    config
    config_remote_vxlan
    add_openflow_rules
    sleep 2

    # icmp
    ip netns exec ns0 ping -q -c 1 -w 2 $REMOTE
    if [ $? -ne 0 ]; then
        err "ping failed"
        return
    fi

    initial_traffic

    title "Start traffic"
    t=16
    ip netns exec ns0 iperf3 -s -D
    on_remote timeout -k1 $((t+2)) iperf3 -c $IP -t $t -P3 &
    pid2=$!

    # verify pid
    sleep 4
    kill -0 $pid2 &>/dev/null
    if [ $? -ne 0 ]; then
        err "iperf failed"
        return
    fi

    ip netns exec ns0 timeout $((t-4)) tcpdump -qnnei $VF -c 30 ip &
    tpid1=$!
    timeout $((t-6)) tcpdump -qnnei $REP -c 10 'tcp' &
    tpid2=$!

    sleep $t
    title "Verify traffic on $VF"
    verify_have_traffic $tpid1
    title "Verify offload on $REP"
    verify_no_traffic $tpid2

    conntrack -L | grep $IP

    kill -9 $pid2 &>/dev/null
    killall -9 iperf3 &>/dev/null
    echo "wait for bgs"
    wait
}

run
ovs-vsctl del-br br-ovs
trap - EXIT
cleanup
test_done
