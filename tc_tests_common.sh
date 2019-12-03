#!/bin/bash

function check_num_rules() {
    local num=$1
    local itf=$2

    title " - check for $num rules"
    RES=`tc -s filter show dev $itf ingress | grep handle | wc -l`
    if (( RES == $num )); then success; else err "Found $RES rules but expected $num"; fi
}

function check_num_offloaded_rules() {
    local num=$1
    local offload_count=$2
    local block=$3

    title " - check for $num rules with in_hw_count=$offload_count"
    RES=`tc -s filter show block $block ingress | grep "in_hw in_hw_count $offload_count" | wc -l`
    if (( RES == $num )); then
        success
    else
        err
    fi
}

function check_num_actions() {
    local count=$1
    local type=$2

    title " - check for $count actions"
    RES=`tc -s actions ls action $type | grep order | wc -l`
    if (( RES == $count )); then success; else err "Found $RES actions but expected $count"; fi
}

function tc_batch() {
    local dup=$1
    local dev_block=$2
    local total=$3
    local rules_per_file=$4
    local cls=$5
    local _action=${action:-drop}
    local n=0
    local count=0
    local handle=0
    local prio=1
    local once=0
    TC_OUT=/tmp/tc-$$
    [ "$incr_prio" == 1 ] && prio=0

    rm -fr $TC_OUT
    mkdir -p $TC_OUT

    for ((i = 0; i < 99; i++)); do
        for ((j = 0; j < 99; j++)); do
            for ((k = 0; k < 99; k++)); do
                for ((l = 0; l < 99; l++)); do
                    SMAC="e4:11:$i:$j:$k:$l"
                    DMAC="e4:12:$i:$j:$k:$l"
                    ((handle+=1))
                    [ "$no_handle" == 1 ] && handle=0
                    [ "$incr_prio" == 1 ] && ((prio+=1))
                    rule="$dev_block \
protocol ip \
ingress \
prio $prio \
handle $handle \
flower \
$skip \
src_mac $SMAC \
dst_mac $DMAC \
$cls \
action $_action $act_flags"

                    [ $once = "0" ] && once=1 && echo "type of rules: $rule"
                    echo "filter add $rule" >> ${TC_OUT}/add.$n
                    echo "filter change $rule" >> ${TC_OUT}/ovr.$n
                    echo "filter del $rule" >> ${TC_OUT}/del.$n

                    ((count+=1))
                    let p=count%${rules_per_file}
                    if ((p==0)); then
                        ((n++))
                        if (($dup==1)); then
                            handle=0
                        fi
                    fi
                    if ((count>=total)); then
                        break;
                    fi
                done
                if ((count>=total)); then
                    break;
                fi
            done
            if ((count>=total)); then
                break;
            fi
        done
        if ((count>=total)); then
            break;
        fi
    done
}

function tc_batch_vxlan() {
    local dev_block=$1
    local total=$2
    local rules_per_file=$3
    local cls=$4
    local id=$5
    local local_ip=$6
    local remote_ip=$7
    local dst_port=$8
    local mirred_dev=$9
    local extra_action=${10}
    local n=0
    local count=0
    local handle=0
    local prio=1
    local once=0
    TC_OUT=/tmp/tc-$$
    [ "$incr_prio" == 1 ] && prio=0

    rm -fr $TC_OUT
    mkdir -p $TC_OUT

    for ((i = 0; i < 99; i++)); do
        for ((j = 0; j < 99; j++)); do
            for ((k = 0; k < 99; k++)); do
                for ((l = 0; l < 99; l++)); do
                    SMAC="e4:11:$i:$j:$k:$l"
                    DMAC="e4:12:$i:$j:$k:$l"
                    ((handle+=1))
                    [ "$no_handle" == 1 ] && handle=0
                    [ "$incr_prio" == 1 ] && ((prio+=1))
                    rule="$dev_block \
protocol ip \
ingress \
prio $prio \
handle $handle \
flower \
$skip \
src_mac $SMAC \
dst_mac $DMAC \
$cls \
$extra_action \
action tunnel_key set id $id src_ip ${local_ip} dst_ip ${remote_ip} dst_port ${dst_port} $act_flags \
action mirred egress redirect dev $mirred_dev $act_flags"

                    [ $once = "0" ] && once=1 && echo "type of rules: $rule"
                    echo "filter add $rule" >> ${TC_OUT}/add.$n
                    echo "filter change $rule" >> ${TC_OUT}/ovr.$n
                    echo "filter del $rule" >> ${TC_OUT}/del.$n

                    ((count+=1))
                    let p=count%${rules_per_file}
                    if ((p==0)); then
                        ((n++))
                    fi
                    if ((count>=total)); then
                        break;
                    fi
                done
                if ((count>=total)); then
                    break;
                fi
            done
            if ((count>=total)); then
                break;
            fi
        done
        if ((count>=total)); then
            break;
        fi
    done
}

function tc_batch_vxlan_multiple_encap() {
    local dev_block=$1
    local total=$2
    local rules_per_file=$3
    local cls=$4
    local id=$5
    local local_ip=$6
    local remote_ip_net=$7
    local remote_ip_host=$8
    local dst_port=$9
    local mirred_dev=${10}
    local encaps_per_file=${11}
    local add_pedit=${12}
    local pedit_act=""
    local remote_ip_start=$8
    local n=0
    local count=0
    local handle=0
    local prio=1
    local once=0
    local rules_per_encap=$((rules_per_file/encaps_per_file))
    TC_OUT=/tmp/tc-$$
    [ "$incr_prio" == 1 ] && prio=0
    if [ $encaps_per_file -gt $rules_per_file ]; then
        local rules_per_encap=$rules_per_file
    fi
    [ $rules_per_encap == 0 ] && fail "rules_per_encap cannot be 0"

    rm -fr $TC_OUT
    mkdir -p $TC_OUT

    for ((i = 0; i < 99; i++)); do
        for ((j = 0; j < 99; j++)); do
            for ((k = 0; k < 99; k++)); do
                for ((l = 0; l < 99; l++)); do
                    SMAC="e4:11:$i:$j:$k:$l"
                    DMAC="e4:12:$i:$j:$k:$l"
                    ((handle+=1))
                    [ "$no_handle" == 1 ] && handle=0
                    [ "$incr_prio" == 1 ] && ((prio+=1))
                    [ "$add_pedit" == 1 ] && pedit_act="action pedit ex munge ip src set ${remote_ip_net}${remote_ip_host}"
                    rule="$dev_block \
protocol ip \
ingress \
prio $prio \
handle $handle \
flower \
$skip \
src_mac $SMAC \
dst_mac $DMAC \
$cls \
$pedit_act \
action tunnel_key set id $id src_ip ${local_ip} dst_ip ${remote_ip_net}${remote_ip_host} dst_port ${dst_port} $act_flags \
action mirred egress redirect dev $mirred_dev $act_flags"

                    [ $once = "0" ] && once=1 && echo "type of rules: $rule"
                    echo "filter add $rule" >> ${TC_OUT}/add.$n
                    echo "filter change $rule" >> ${TC_OUT}/ovr.$n
                    echo "filter del $rule" >> ${TC_OUT}/del.$n

                    ((count+=1))
                    let p=count%${rules_per_file}
                    let e=count%${rules_per_encap}
                    if ((p==0)); then
                        ((n++))
                        remote_ip_host=$remote_ip_start
                    elif ((e==0)); then
                        ((remote_ip_host++))
                    fi

                    if ((count>=total)); then
                        break;
                    fi
                done
                if ((count>=total)); then
                    break;
                fi
            done
            if ((count>=total)); then
                break;
            fi
        done
        if ((count>=total)); then
            break;
        fi
    done
}

declare -A current
declare -A goal

function key_val_to_array() {
    local -n arr=$1
    local key
    local value

    while IFS== read -r key value; do
        arr[$key]=$value
    done
}

function check_test_results() {
    local -n arr1=$1
    local -n arr2=$2

    for m in "${!arr1[@]}"
    do
        # Calculate absolute difference between baseline time and this test run (per cent).
        read abs_diff <<< $(awk -v v1="${arr2[$m]}" -v v2="${arr1[$m]}" 'BEGIN{diff=(v2-v1)/v1 * 100;abs=diff<0?-diff:diff; printf "%.0f", abs}')
        if ((abs_diff > 10)); then
            err "Measured value for $m (current=${arr2[$m]} reference=${arr1[$m]}) differs by $abs_diff per cent"
        else
            success "Measured value for $m (current=${arr2[$m]} reference=${arr1[$m]}) differs by $abs_diff per cent"
        fi
    done
}

function run_perf_test() {
    local input_file="$1"
    local test_type="$2"
    local num_rules="$3"
    local num_instances="$4"
    local flower_flags="$5"
    local action_flags="$6"

    # Skip all test output until results
    local res
    res=`$DIR/test-tc-perf-update.sh "$test_type" "$num_rules" "$num_instances" "$flower_flags" "$action_flags"`
    local rc=$?
    if [ $rc -ne 0 ]; then
        fail "Perf update test failed"
    fi

    res=`echo $res | sed -n '/^RESULTS:$/,$p' | tail -n +2`

    if [ -f "$input_file" ]; then
        key_val_to_array current < <(echo "$res")
        key_val_to_array goal < "$input_file"
        check_test_results goal current
    else
        title "No input file found. Create file $input_file."
        echo "$res" > "$input_file" && success || fail "Failed to write results"
    fi
}

