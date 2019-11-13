#!/bin/bash
#
# This test measures performance of tc rules update. It inserts/deletes
# arbitrary number of rules (L2, 5-tuple, vxlan, pedit, and their combinations)
# in single instance or multi instance tc mode. Baseline rate/memory values
# should be set in per-setup configuration file.
#
# IGNORE_FROM_TEST_ALL
#

profile=${1:-all}
total=${2:-100000}
num_tc=${3:-1}
skip=$4
act_flags=$5
let per_file=$total/$num_tc

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/tc_tests_common.sh

echo "setup"
config_sriov 2 $NIC
enable_switchdev_if_no_rep $REP
bind_vfs $NIC

local_ip="2.2.2.2"
remote_ip_net="2.2.2."
remote_ip_host="3"
dst_mac="e4:1d:2d:fd:8b:02"
vxlan_mac="e4:1d:2d:fd:8b:04"
dst_port=4789
id=1
vxlan_dev="vxlan1"
num_encaps=100

classifier_5t="src_ip 192.168.111.1 dst_ip 192.168.111.2 ip_proto udp dst_port 1 src_port 1"
action_edit="action pedit ex munge ip src set 2.2.2.200"

declare -A results

function setup_vxlan() {
    ip link add $vxlan_dev type vxlan id $id dev $NIC dstport $dst_port
    ip addr add $local_ip dev $NIC
    ip link set $vxlan_dev up
}

function cleanup_vxlan() {
    ip link del dev $vxlan_dev 2> /dev/null
    ip addr flush dev $NIC
}

function set_neighs() {
    local num_encaps="$1"
    local remote_ip_net="$2"
    local remote_ip_host="$3"
    local clear="$4"

    for ((i = 0; i < num_encaps; i++)); do
        if [ "$clear" == 1 ]
        then ip neigh del ${remote_ip_net}${remote_ip_host} dev $NIC
        else ip neigh add ${remote_ip_net}${remote_ip_host} lladdr ${vxlan_mac} dev $NIC
        fi

        ((remote_ip_host++))
    done
}

function run_multi_tc() {
    local file_name=$1

    # Spawn tc instance per batch file and measure execution time. Save 'time' output to out
    out=$( { time -p ls ${TC_OUT}/${file_name}.* | xargs -n 1 -P 100 tc -b; } 2>&1 1>/dev/null )
    # Extract 'real' time
    [[ $out =~ [^0-9]*([0-9]+\.[0-9]+) ]]
    real_time="${BASH_REMATCH[1]}"

    echo $real_time
}

function run_benchmark_time() {
    local file_name=$1
    local dev=$2
    local num_rules=$3
    local time=$4

    exec_time=$(run_multi_tc $file_name)
    # Calculate rules insertion rate in k rules/sec
    results[$time]=$(echo "scale=1; $total/($exec_time * 1000)" | bc -l)

    check_num_rules $num_rules $dev
}

function calc_used_mem() {
    vmstat -s | grep -i "used memory" | awk {'print $1'}
}

function run_benchmark_time_mem() {
    local file_name=$1
    local dev=$2
    local num_rules=$3
    local rate=$4
    local mem=$5
    local exec_time

    local used_mem_start=$(calc_used_mem)

    exec_time=$(run_multi_tc $file_name)

    # Calculate rules insertion rate in k rules/sec
    results[$rate]=$(echo "scale=2; $total/($exec_time * 1000)" | bc -l)

    local used_mem_end=$(calc_used_mem)
    # Calculate KB memory used per rule with fractional part
    results[$mem]=$(echo "scale=2; ($used_mem_end - $used_mem_start)/$total" | bc -l)

    check_num_rules $num_rules $dev
}

function perf_test() {
    local rules_per_file=$1
    local classifier=$2
    local ins_rate=$3
    local del_rate=$4
    local used_mem=$5

    tc_batch 0 "dev $NIC" $total $rules_per_file "$classifier"
    reset_tc $NIC

    echo "Insert rules"
    run_benchmark_time_mem add $NIC $total $ins_rate $used_mem

    echo "Delete rules"
    run_benchmark_time del $NIC 0 $del_rate
}

function perf_test_vxlan() {
    local rules_per_file=$1
    local classifier=$2
    local extra_action=$3
    local ins_rate=$4
    local del_rate=$5
    local used_mem=$6

    reset_tc $REP
    setup_vxlan
    set_neighs 1 $remote_ip_net $remote_ip_host 0

    tc_batch_vxlan "dev $REP" $total $rules_per_file "$classifier" $id $local_ip "${remote_ip_net}${remote_ip_host}" $dst_port $vxlan_dev "$extra_action"

    echo "Insert rules"
    run_benchmark_time_mem add $REP $total $ins_rate $used_mem

    echo "Delete rules"
    run_benchmark_time del $REP 0 $del_rate

    set_neighs 1 $remote_ip_net $remote_ip_host 1
    cleanup_vxlan
}

function perf_test_vxlan_multi() {
    local rules_per_file=$1
    local classifier=$2
    local pedit=$3
    local ins_rate=$4
    local del_rate=$5
    local used_mem=$6

    reset_tc $REP
    setup_vxlan
    set_neighs $num_encaps $remote_ip_net $remote_ip_host 0

    tc_batch_vxlan_multiple_encap "dev $REP" $total $rules_per_file "$classifier" $id $local_ip $remote_ip_net $remote_ip_host $dst_port $vxlan_dev $num_encaps $pedit

    echo "Insert rules"
    run_benchmark_time_mem add $REP $total $ins_rate $used_mem

    echo "Delete rules"
    run_benchmark_time del $REP 0 $del_rate

    set_neighs $num_encaps $remote_ip_net $remote_ip_host 1
    cleanup_vxlan
}

function test_l2() {
    title "Test $num_tc tc instance(s) with $total L2 rules"
    perf_test $per_file "" L2_INSERT_K_RULES_SEC L2_DELETE_K_RULES_SEC L2_MEMORY_K_PER_RULE
}

function test_l2_5t() {
    title "Test $num_tc tc instance(s) with $total L2+5tuple rules"
    perf_test $per_file "$classifier_5t" L2_5T_INSERT_K_RULES_SEC L2_5T_DELETE_K_RULES_SEC L2_5T_MEMORY_K_PER_RULE
}

function test_encap() {
    title "Test $num_tc tc instance(s) with $total vxlan encap L2+5tuple rules"
    perf_test_vxlan $per_file "$classifier_5t" " " ENCAP_INSERT_K_RULES_SEC ENCAP_DELETE_K_RULES_SEC ENCAP_MEMORY_K_PER_RULE
}

function test_pedit_encap() {
    title "Test $num_tc tc instance(s) with $total vxlan encap and pedit L2+5tuple rules"
    perf_test_vxlan $per_file "$classifier_5t" "$action_edit" PEDIT_ENCAP_INSERT_K_RULES_SEC PEDIT_ENCAP_DELETE_K_RULES_SEC PEDIT_ENCAP_MEMORY_K_PER_RULE
}

function test_multi_encap() {
    title "Test $num_tc tc instance(s) with $total vxlan encap (multi instance) L2+5tuple rules"
    perf_test_vxlan_multi $per_file "$classifier_5t" 0 MULTI_ENCAP_INSERT_K_RULES_SEC MULTI_ENCAP_DELETE_K_RULES_SEC MULTI_ENCAP_MEMORY_K_PER_RULE
}

function test_multi_pedit_encap() {
    title "Test $num_tc tc instance(s) with $total vxlan encap and pedit (multi instance) L2+5tuple rules"
    perf_test_vxlan_multi $per_file "$classifier_5t" 1 MULTI_PEDIT_ENCAP_INSERT_K_RULES_SEC MULTI_PEDIT_ENCAP_DELETE_K_RULES_SEC MULTI_PEDIT_ENCAP_MEMORY_K_PER_RULE
}

declare -A tests
tests=( ["l2"]="test_l2"
        ["5t"]="test_l2_5t"
        ["encap"]="test_encap"
        ["pedit_encap"]="test_pedit_encap"
        ["multi_encap"]="test_multi_encap"
        ["multi_pedit_encap"]="test_multi_pedit_encap" )

if [ "all" == "$profile" ]
then
    for t in "${!tests[@]}"
    do ${tests[$t]}
    done
elif [ -z "${tests[$profile]}" ]
then
    err "Unrecognized test $profile"
else
    ${tests[$profile]}
fi

echo "RESULTS:"
for res in "${!results[@]}"
do
    echo "$res=${results[$res]}"
done
