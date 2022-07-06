#!/bin/bash
#
# Verify traffic between VFs on BlueField
#

my_dir="$(dirname "$0")"
. $my_dir/common-bf-test.sh

require_interfaces NIC
require_bf

CLIENT_NS=ns0
CLIENT_VF=$VF
CLIENT_REP=$REP
CLIENT_IPV4=7.7.7.1
CLIENT_IPV6=7:7:7::1

SERVER_NS=ns1
SERVER_VF=$VF2
SERVER_REP=$REP2
SERVER_IPV4=7.7.7.2
SERVER_IPV6=7:7:7::2

BRIDGE="bf-br"

function clean_up_test() {
    on_bf_exec "start_clean_openvswitch"
    ip -all netns del
}

function config_test() {
    config_sriov

    require_interfaces CLIENT_VF SERVER_VF
    config_vf $CLIENT_NS $CLIENT_VF $CLIENT_REP $CLIENT_IPV4
    ip netns exec $CLIENT_NS ip addr add $CLIENT_IPV6/64 dev $CLIENT_VF

    config_vf $SERVER_NS $SERVER_VF $SERVER_REP $SERVER_IPV4
    ip netns exec $SERVER_NS ip addr add $SERVER_IPV6/64 dev $SERVER_VF

    on_bf_exec "start_clean_openvswitch
           ovs-vsctl --may-exist add-br $BRIDGE -- --may-exist add-port $BRIDGE $CLIENT_REP -- --may-exist add-port $BRIDGE $SERVER_REP
           ip link set $BF_NIC up"
}

function run_test() {
    title "Test ICMP traffic between $CLIENT_VF($CLIENT_IPV4) -> $SERVER_VF($SERVER_IPV4)"
    ip netns exec $CLIENT_NS ping -w 4 $SERVER_IPV4 && success || err "icmp failed"

    title "Test ICMP6 traffic between $CLIENT_VF($CLIENT_IPV6) -> $SERVER_VF($SERVER_IPV6)"
    ip netns exec $CLIENT_NS ping -w 4 $SERVER_IPV6 && success || err "icmp6 failed"
}

clean_up_test
trap clean_up_test EXIT

config_test
run_test

trap - EXIT
clean_up_test

test_done
