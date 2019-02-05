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

    title " - check for $num rules"
    RES=`tc -s filter show block $block ingress | grep "in_hw in_hw_count $offload_count" | wc -l`
    if (( RES == $num )); then
        success
    elif (( `tc -s filter show block $block ingress | grep -w in_hw | wc -l` == $num )); then
        log "Kernel/tc doesn't support in_hw_count, fallback to count rules in hw"
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
action $_action"

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
