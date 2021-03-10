#!/bin/bash
#
# Test OVS CT with traffic and VF LAG
#
# Scrum Task #1837751: Add support for CT with VF LAG
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh
pktgen=$my_dir/scapy-traffic-tester.py

require_module act_ct bonding

require_remote_server
if [ -z "$REMOTE_NIC2" ]; then
    fail "Remote nic2 is not configured"
fi

IP=1.1.1.7
REMOTE=1.1.1.8


function config_ports() {
    config_sriov 2
    config_sriov 2 $NIC2
    enable_switchdev
    enable_switchdev $NIC2
    require_interfaces REP NIC
    unbind_vfs
    config_bonding $NIC $NIC2
    fail_if_err
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

function cleanup_remote() {
    clear_remote_bonding
    on_remote "ip a flush dev $REMOTE_NIC ; ip a flush dev $REMOTE_NIC2" &>/dev/null
}

function cleanup() {
    cleanup_remote
    ip netns del ns0 &>/dev/null
    ip netns del ns1 &>/dev/null
    sleep 0.5
    unbind_vfs
    sleep 1
    clear_bonding
    config_sriov 0 $NIC2
    ip a flush dev $NIC
}
trap cleanup EXIT

function config() {
    cleanup
    config_ports
    set_nf_liberal
    conntrack -F
    ifconfig bond0 up
    ip netns add ns0
    ip link set dev $VF netns ns0
    ip netns exec ns0 ifconfig $VF $IP/24 up

    echo "Restarting OVS"
    start_clean_openvswitch

    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs bond0

    # WA bug ovs not getting netdev event for slave to add the shared block
    for n in $NIC $NIC2; do
        ip link set down $n
        ip link set up $n
    done
}

function config_remote() {
    remote_disable_sriov
    config_remote_bonding
    on_remote ip a add $REMOTE/24 dev bond0
    on_remote ip l set dev bond0 up
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

function run_server() {
    ssh2 $REMOTE_SERVER timeout $((t+2)) iperf -s -t $t &
#    ssh2 $REMOTE_SERVER $pktgen -l -i $REMOTE_NIC --src-ip $IP --time $((t+1)) &
    pk1=$!
    sleep 2
}

function run_client() {
    ip netns exec ns0 timeout $((t+2)) iperf -c $REMOTE -t $t -P3 &
#    ip netns exec ns0 $pktgen -i $VF --src-ip $IP --dst-ip $REMOTE --time $t --pkt-count 2 --inter 1 &
    pk2=$!
}

function kill_traffic() {
    kill -9 $pk1 &>/dev/null
    kill -9 $pk2 &>/dev/null
    wait $pk1 $pk2 2>/dev/null
}

function run() {
    config
    config_remote
    add_openflow_rules

    if [ "$B2B" == 1 ]; then
        # set local and remote to the same port
        echo $active_slave > /sys/class/net/bond0/bonding/active_slave
        on_remote "echo $remote_active > /sys/class/net/bond0/bonding/active_slave"
    fi

    # icmp
    ip netns exec ns0 ping -q -c 1 -w 1 $REMOTE
    if [ $? -ne 0 ]; then
        err "ping failed"
        return
    fi

    t=15
    # traffic
    run_server
    run_client

    # verify pid
    sleep 2
    kill -0 $pk1 &>/dev/null
    p1=$?
    kill -0 $pk2 &>/dev/null
    p2=$?
    if [ $p1 -ne 0 ] || [ $p2 -ne 0 ]; then
        err "traffic failed"
        return
    fi

    sleep 1
    title "reconfig ovs during traffic"
    add_openflow_rules
    sleep 6

    timeout $((t-6)) tcpdump -qnnei $REP -c 30 'tcp' &
    tpid=$!

    sleep $t
    verify_no_traffic $tpid

    conntrack -L | grep $IP

    kill_traffic
    echo "wait for bgs"
    wait

    iterate_bond_slaves
}

function iterate_bond_slaves() {
    title "iterate bond slaves"
    for i in `seq 3`; do
        title "Iter $i"
        change_slaves
        count1=`get_rx_pkts $slave1`
        t=10
        run_server
        run_client
        sleep 2
        echo "wait"
        sleep $t
        kill_traffic
        wait
        count2=`get_rx_pkts $slave1`
        ((count1+=100))
        if [ "$count2" -lt "$count1" ]; then
            err "No traffic?"
        fi
    done
}

slave1=$NIC
slave2=$NIC2
active_slave=$NIC
remote_active=$REMOTE_NIC
function change_slaves() {
    title "change active slave from $slave1 to $slave2"
    local tmpslave=$slave1
    slave1=$slave2
    slave2=$tmpslave
    ifconfig $tmpslave down
    sleep 0.5
    ifconfig $tmpslave up

    if [ "$B2B" == 1 ]; then
        if [ "$remote_active" == $REMOTE_NIC ]; then
            remote_active=$REMOTE_NIC2
        else
            remote_active=$REMOTE_NIC
        fi
        on_remote "echo $remote_active > /sys/class/net/bond0/bonding/active_slave"
    fi
}

start_check_syndrome
run
start_clean_openvswitch
cleanup
check_syndrome
trap - EXIT
test_done
