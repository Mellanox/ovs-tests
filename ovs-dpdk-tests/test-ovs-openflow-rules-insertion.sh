#!/bin/bash
#
# Test OVS is capable to add 4k rules per second.
# Feature Request #3494640: [HBN] [OVS-DOCA] 4K Openflow per sec on Bluefield-3.
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

config_sriov 2
require_interfaces REP NIC
unbind_vfs
bind_vfs

trap cleanup_test EXIT

number_of_rules=${1:-4000}
output_file="/tmp/openflow_batch_$$"
br=br-ovs

function config() {
    echo > $output_file
    start_clean_openvswitch
    ovs-vsctl add-br $br
}

function create_openflow_rules_port_change_batch() {
    title "Creating openflow rules batch with port change"
    for i in `seq 1 $number_of_rules`; do
        echo "ip,tcp,tcp_src=$i,action=drop" >> $output_file
    done
}

function create_openflow_rules_mac_change_batch() {
    title "Creating openflow rules batch with mac change"
    local mac
    local count=0

    for ((i = 0; i < 99; i++)); do
        for ((j = 0; j < 99; j++)); do
            for ((k = 0; k < 99; k++)); do
                for ((l = 0; l < 99; l++)); do
                    mac="e4:11:$i:$j:$k:$l"
                    echo "ip,tcp,dl_src=$mac,dl_dst=$mac, action=drop" >> $output_file
                    let count=count+1
                    [ $count -eq $number_of_rules ] && return
                done
            done
        done
    done
}

function test_time_cmd() {
    local x=$1
    local cmd=$2
    local t1=`get_ms_time`
    time $cmd
    local t2=`get_ms_time`
    let t=t2-t1
    if [ $t -gt $x ]; then
        err "Took $t but expected less than $x ms"
    else
        success "took $t ms (max $x)"
    fi
}

function apply_batch() {
    title "Apply openflow rule batch"
    test_time_cmd 1000 "ovs-ofctl add-flows $br $output_file"
    local rules=`ovs-appctl bridge/dump-flows $br | wc -l`

    if [ $rules -lt $number_of_rules ]; then
        err "Expected at least $number_of_rules and found only $rules"
    else
        success "Found $rules which is more than $number_of_rules"
    fi
}

function run() {
    config
    create_openflow_rules_port_change_batch
    apply_batch
    ovs-ofctl del-flows $br
    echo > $output_file
    create_openflow_rules_mac_change_batch
    apply_batch
}

run
trap - EXIT
cleanup_test
test_done
