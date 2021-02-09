#!/bin/bash
#
# Test modify tuple non-CT flows offloading not affected by CT flows matching
#
# Bug SW #2482558: flows with match on ct state without action ct are not offloaded

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module act_ct

IP1="7.7.7.1"
IP2="7.7.7.2"

enable_switchdev
require_interfaces REP REP2
unbind_vfs
bind_vfs
reset_tc $REP
reset_tc $REP2

function cleanup() {
    ip netns del ns0 2> /dev/null
    ip netns del ns1 2> /dev/null
    reset_tc $REP &>/dev/null
    reset_tc $REP2 &>/dev/null
}
trap cleanup EXIT

function config_ovs() {
    local proto=$1

    echo "setup ovs"
    start_clean_openvswitch

    ovs-vsctl add-br br-ovs

    ovs-appctl vlog/set dpif_netlink:dbg
    ovs-appctl vlog/set ofproto_dpif_upcall:dbg
    ovs-appctl vlog/set netdev_offload_tc:dbg
    ovs-appctl vlog/set ofproto_dpif_xlate:dbg

    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs $REP2

    ovs-ofctl add-flow br-ovs in_port=$REP,dl_type=0x0806,actions=output:$REP2
    ovs-ofctl add-flow br-ovs in_port=$REP2,dl_type=0x0806,actions=output:$REP

    ovs-ofctl add-flow br-ovs "dl_src=00:00:00:00:02:01,dl_dst=00:00:00:00:03:02,in_port=$REP,ct_state=-trk,ip actions=ct";
    ovs-ofctl add-flow br-ovs "dl_src=00:00:00:00:03:02,dl_dst=00:00:00:00:02:01,in_port=$REP2,ct_state=-trk,ip actions=ct";

    ovs-ofctl add-flow br-ovs "dl_src=00:00:00:00:03:01,dl_dst=00:00:00:00:03:02,in_port=$REP,udp,tp_dst=19051 actions=mod_tp_dst:19052,output:$REP2"
    ovs-ofctl add-flow br-ovs "dl_src=00:00:00:00:03:02,dl_dst=00:00:00:00:03:01,in_port=$REP2,udp,tp_src=19052 actions=mod_tp_src:19051,output:$REP"

    ovs-ofctl add-flow br-ovs "dl_src=00:00:00:00:02:01,dl_dst=00:00:00:00:03:02,in_port=$REP,ct_state=+new+trk,ip actions=ct(commit),output:$REP2";
    ovs-ofctl add-flow br-ovs "dl_src=00:00:00:00:02:01,dl_dst=00:00:00:00:03:02,in_port=$REP,ct_state=+est+trk,ip actions=output:$REP2"
    ovs-ofctl add-flow br-ovs "dl_src=00:00:00:00:03:02,dl_dst=00:00:00:00:02:01,in_port=$REP2,ct_state=+new+trk,ip actions=ct(commit),output:$REP";
    ovs-ofctl add-flow br-ovs "dl_src=00:00:00:00:03:02,dl_dst=00:00:00:00:02:01,in_port=$REP2,ct_state=+est+trk,ip actions=output:$REP";

    ovs-ofctl dump-flows br-ovs --color
}

function run() {
    title "Test OVS CT UDP"
    config_vf ns0 $VF $REP $IP1 00:00:00:00:03:01
    config_vf ns1 $VF2 $REP2 $IP2 00:00:00:00:03:02

    proto="udp"
    config_ovs $proto

    t=10
    echo "run traffic for $t seconds"
    ip netns exec ns1 iperf -u -B $IP2 -p 19052 -i 1 -s &
    sleep 1
    ip netns exec ns0 iperf -u -B $IP1 -c $IP2 -p 19051 -i 1 -t $t &
    sleep $((t / 2))

    title "---> OFFLOADED <---"
    ovs-appctl dpctl/dump-flows --names -m type=offloaded \
    | egrep --color=always '(arp|ipv[46]?|udp|tcp)|\$' # highlight keywords
    title "---> OFFLOADED <---"

    title "---> NON-OFFLOADED <---"
    ovs-appctl dpctl/dump-flows --names -m type=non-offloaded \
    | egrep --color=always '(arp|ipv[46]?|udp|tcp)|\$' # highlight keywords
    title "---> NON-OFFLOADED <---"

    wait %2
    kill %1

    ovs-ofctl dump-flows br-ovs --color

    not_offloaded=$(ovs-appctl dpctl/dump-flows --names -m type=non-offloaded \
                    | grep --perl-regexp --color=always 'udp.*?(dst|src)=1905[12]')
    if [[ -n $not_offloaded ]] ; then
        err "UDP port rewrite flows were not offloaded:"
        echo -e "$not_offloaded"
    fi

    ovs-vsctl del-br br-ovs
}


run
test_done
