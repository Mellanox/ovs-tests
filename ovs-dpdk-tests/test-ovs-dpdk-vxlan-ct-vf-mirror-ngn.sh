#!/bin/bash
#
# Test OVS with vxlan traffic with local mirroring before and after CT
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

config_sriov 2
enable_switchdev
bind_vfs
trap clean_ EXIT

function clean_() {
    kill -9 $tcpdump_pid &>/dev/null
    cleanup_test
}

function config() {
    cleanup_test

    config_tunnel "vxlan"
    config_remote_tunnel "vxlan"
    config_local_tunnel_ip $LOCAL_TUN_IP br-phy
    add_local_mirror $IB_PF0_PORT1 1 br-int

    ifconfig $VF2 0 up
}

function add_openflow_rules() {
    ovs_add_ct_rules br-int

    #replace est rule with another mirror
    ovs-ofctl del-flows br-int "table=1,ct_state=+est+trk,ip"
    ovs-ofctl add-flow br-int "table=1,ct_state=+est+trk,ip,actions=$IB_PF0_PORT1,NORMAL"
}

function run() {
    config
    add_openflow_rules

    # icmp
    verify_ping $REMOTE_IP ns0

    ethtool -K $VF2 gro off lro off
    tcpdump -nnei $VF2 -S -c 100000 -vv > /tmp/mirror_tcpdump &

    tcpdump_pid=$!
    iperf_client_extra_args="--bidir"
    generate_traffic "remote" $LOCAL_IP

    kill -0 $tcpdump_pid &>/dev/null

    reply=`cat /tmp/mirror_tcpdump | grep "${LOCAL_IP}.5201 > $REMOTE_IP" | grep -o ".*seq [0-9]\+, ack [0-9]\+"`
    reply_cnt=`echo "$reply" | wc -l`
    reply_uniq_cnt=`echo "$reply" | sort | uniq | wc -l`

    orig=`cat /tmp/mirror_tcpdump | grep "${REMOTE_IP}.* > ${LOCAL_IP}.5201" | grep -o "seq [0-9]\+:[0-9]\+"`
    orig_cnt=`echo "$orig" | wc -l`
    orig_uniq_cnt=`echo "$orig" | sort | uniq | wc -l`

    title "Check tcpdump for packet duplication on mirror"
    if (($reply_cnt <= 0)) || (($orig_cnt <= 0)) ||
       (($reply_cnt * 1000 / $reply_uniq_cnt <= 1500)) ||
       (($reply_cnt * 1000 / $reply_uniq_cnt >= 2500)) ||
       (($orig_cnt * 1000 / $orig_uniq_cnt <= 1500)) ||
       (($orig_cnt * 1000 / $orig_uniq_cnt >= 2500)); then
        fail "Couldn't capture correct packet duplication number $orig_cnt $orig_uniq_cnt @ $reply_cnt $reply_uniq_cnt"
    fi
}

run
trap - EXIT
clean_
test_done
