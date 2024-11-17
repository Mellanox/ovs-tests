#!/bin/bash
#
# Test OVS GRE: with and without key

my_dir="$(dirname "$0")"
. $my_dir/common.sh


VM1_IP="7.7.7.1"
VM2_IP="7.7.7.2"

local_tun="2.2.2.2"
remote_tun="2.2.2.3"


function cleanup() {
    ip l del dev gre_sys &>/dev/null
    ip netns del ns0 &> /dev/null

    for i in `seq 0 3`; do
        ip link del veth$i &> /dev/null
    done
}
trap cleanup EXIT

function create_gre_tunnel() {
    local grekey=$KEY
    local ovsop=""

    echo "cleanup"
    start_clean_openvswitch
    cleanup

    echo "setup veth and ns"
    ip link add veth0 type veth peer name veth1
    ip link add veth2 type veth peer name veth3
    ifconfig veth2 $local_tun/24 up
    ifconfig veth0 $VM1_IP/24 up
    ifconfig veth1 up

    ip netns add ns0
    ip link set veth3 netns ns0
    ip netns exec ns0 ifconfig veth3 $remote_tun/24 up

    if [[ $KEY != "nokey" ]]; then
        grekey="key $KEY"
        ovsop="options:key=$KEY"
    fi
    echo "setup gre $grekey"

    ip netns exec ns0 ip link add name gre_sys type gretap dev veth3 remote $local_tun nocsum $grekey || fail "Failed to create gre interface"
    ip netns exec ns0 ifconfig gre_sys $VM2_IP/24 up
    sleep 2

    echo "setup ovs"
    ovs-vsctl add-br brv-1
    ovs-vsctl add-port brv-1 veth1
    ovs-vsctl add-port brv-1 gre0 -- set interface gre0 type=gre options:local_ip=$local_tun options:remote_ip=$remote_tun $ovsop
}

function check_offloaded_rules() {
    local count=$1
    title " - check for $count offloaded rules"

    if [[ $KEY == "nokey" ]]; then
        RES="ovs_dump_tc_flows --names | grep 0x0800 | grep -v drop | grep gre_sys | grep -vw key"
    else
        RES="ovs_dump_tc_flows --names | grep 0x0800 | grep -v drop | grep gre_sys | grep -w key"
    fi
    eval $RES
    RES=`eval $RES | wc -l`
    if (( RES == $count )); then success; else err; fi
}

function do_traffic() {
    ping -q -c 10 -i 0.2 -w 4 $VM2_IP && success || err
}

function remove_gre_modules() {
    local holders=`ls -1r /sys/module/gre/holders`
    modprobe -r $holders gre
}

title "Test gre tunnel with key $KEY"
KEY=5
create_gre_tunnel
do_traffic
check_offloaded_rules 2

title "Test gre tunnel without a key"
KEY=nokey
create_gre_tunnel
do_traffic
check_offloaded_rules 2
ovs_clear_bridges

echo "cleanup"
cleanup
remove_gre_modules
test_done
