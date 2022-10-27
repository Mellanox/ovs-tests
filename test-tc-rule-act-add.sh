#!/bin/bash
#
# This verifies basic tc filter and action functionality. Performs sanity test
# of rule/action reference counting and verifies basic assumptions about tc API
# behavior. (can't delete bound actions, etc.)

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/tc_tests_common.sh

action_type=$1
skip=$2

echo "setup"
config_sriov 2 $NIC
enable_switchdev

require_interfaces NIC REP
reset_tc $NIC
reset_tc $REP

# This array defines action_type->action_text mapping
declare -A actions
actions=( ["csum"]="action csum ip4h udp"
          ["gact"]="action drop"
          ["mirred"]="action mirred egress redirect dev $REP"
          ["pedit"]="action pedit munge ip dport set 10"
          ["skbedit"]="action skbedit priority 10"
          ["tunnel_key"]="action tunnel_key set src_ip 192.168.1.1 dst_ip 192.168.1.2 id 7"
          ["vlan"]="action vlan pop"
          ["ct"]="action ct"
          ["police"]="action police rate 1mbit burst 100k"
          ["sample"]="action sample rate 100 group 12"
          ["mpls"]="action mpls push protocol mpls_uc label 123" )

# This array allows to specify estimator per action type
declare -A action_to_estimator
action_to_estimator=( ["vlan"]="estimator 1sec 2sec" )

function eval_cmd() {
    title "$1"
    eval "$2"
    local err=$?
    test $err != 0 && err "Command failed ($err): $2" && return
    sleep 0.4
    check_num_rules $3 $NIC
    check_num_actions $4 $5
}

function eval_cmd_err() {
    title "$1"
    eval "$2"
    local err=$?
    test $err == 0 && err "Expected command failure: $2" && return
    sleep 0.4
    check_num_rules $3 $NIC
    check_num_actions $4 $5
}

function add_del_rule() {
    local act_type=$1
    local act="${actions[$act_type]}"
    local estimator=${action_to_estimator[$act_type]}
    local spec="dev $NIC protocol ip"
    local qdisc="ingress prio 10"
    local rule="flower $skip dst_mac e4:11:22:33:44:50 ip_proto udp dst_port 1 src_port 1"
    local rule2="flower $skip dst_mac e4:11:22:33:44:70 ip_proto udp dst_port 1 src_port 2"

    #module was not compiled
    modprobe -q act_$act_type
    if [ $? -ne 0 ]; then
        log "Didn't find act_${act_type}. skipping."
        return 0
    fi
    title "Test add_del_rule for act_$act_type"

    eval_cmd "Add rule with $act_type" "tc filter add $spec $qdisc handle 1 $estimator $rule $act index 1" 1 1 $act_type
    eval_cmd_err "Verify that rule duplicate is rejected" "tc filter add $spec $qdisc handle 1 $rule $act index 1" 1 1 $act_type
    eval_cmd_err "Verify that act duplicate is rejected" "tc actions add $act index 1" 1 1 $act_type
    eval_cmd_err "Verify that act delete is rejected" "tc actions del action $act_type index 1" 1 1 $act_type
    eval_cmd_err "Verify that act delete is rejected again" "tc actions del action $act_type index 1" 1 1 $act_type
    eval_cmd "Verify that rule overwrite is accepted" "tc filter change $spec $qdisc handle 1 $estimator $rule $act index 1" 1 1 $act_type
    eval_cmd "Bind rule to existing action" "tc filter add $spec $qdisc handle 2 $rule2 $act index 1" 2 1 $act_type
    eval_cmd "Verify that only first rule is deleted" "tc filter del $spec $qdisc handle 1 flower" 1 1 $act_type
    eval_cmd "Verify that second rule and action are deleted" "tc filter del $spec $qdisc handle 2 flower" 0 0 $act_type

}

function add_del_act() {
    local act_type=$1
    local act="${actions[$act_type]}"

    #module was not compiled
    modprobe -q act_$act_type || return 0
    title "Test add_del_act for act_$act_type"

    tc actions flush action $act_type || err "action $act_type flush failed"

    eval_cmd "Add act $act_type" "tc actions add $act index 1" 0 1 $act_type
    eval_cmd_err "Verify that act duplicate is rejected" "tc actions add $act index 1" 0 1 $act_type
    eval_cmd "Verify that act overwrite is accepted" "tc actions change $act index 1" 0 1 $act_type
    eval_cmd "Verify that act is deleted" "tc actions del action $act_type index 1" 0 0 $act_type

    tc actions flush action $act_type || err "action $act_type flush failed"
}

if [ -z "$action_type" ]
then
    for act in "${!actions[@]}"
    do
        add_del_rule $act
        add_del_act $act
    done
elif [ -z "${actions[$action_type]}" ]
then
    err "Unrecognized action type: $action_type"
else
    add_del_rule $action_type
    add_del_act $action_type
fi

test_done
