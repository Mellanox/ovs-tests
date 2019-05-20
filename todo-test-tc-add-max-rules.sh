#!/bin/bash
#
# Bug SW #900706: Adding 42K flows results in a fw error
#
# IGNORE_FROM_TEST_ALL

my_dir="$(dirname "$0")"
. $my_dir/common.sh


SKIP=${SKIP:-skip_sw}
SMAC=${SMAC:-1}
DMAC=${DMAC:-1}
TOTAL_COUNT=${TOTAL_COUNT:-30000}
TIMEOUT=${TIMEOUT:-5m}
NIC1=${NIC_1:-$NIC}
NIC2=${NIC_2:-$REP}
ACTION=${ACTION:-drop}

require_interfaces NIC1
if [ "$ACTION" == "mirred" ]; then
    require_interfaces NIC2
fi


function tc_batch() {
    local dev_block=$1
    local total=$2
    local cls=$3
    local n=0
    local count=0
    local handle=0
    local once=0
    TC_OUT=/tmp/tc-$$

    rm -fr $TC_OUT
    mkdir -p $TC_OUT

    for ((i = 0; i < 99; i++)); do
        for ((j = 0; j < 99; j++)); do
            for ((k = 0; k < 99; k++)); do
                for ((l = 0; l < 99; l++)); do
                    [ $SMAC = "1" ] && _SMAC="src_mac e4:11:$i:$j:$k:$l"
                    [ $DMAC = "1" ] && _DMAC="dst_mac e4:12:$i:$j:$k:$l"
                    ((handle+=1))
                    rule="$dev_block \
protocol ip \
ingress \
prio 1 \
handle $handle \
flower \
$SKIP \
ip_proto udp \
src_ip 1.1.1.1 \
$_SMAC \
$_DMAC \
$cls \
action $ACTION"

                    echo "filter add $rule" >> ${TC_OUT}/add.$n
                    [ $once = "0" ] && once=1 && echo "type of rules: $rule"

                    ((count+=1))
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

function get_used_mem() {
    vmstat -s | grep -i "used memory" | awk {'print $1'}
}

function tc_batch1() {
    echo "generating rules file"
    tc_batch "$1" $2 $3
    echo "add rules"
    memused1=`get_used_mem`
    time timeout $TIMEOUT tc -b ${TC_OUT}/add.*
    rc=$?
    if [ $rc == "0" ]; then
        success
        memused2=`get_used_mem`
        mem_per_rule=`echo "scale=2; ($memused2-$memused1)/$TOTAL_COUNT" | bc`
        echo "avg mem per rule is $mem_per_rule kb"
    elif [ $rc == "124" ]; then
        err "Timed out after $TIMEOUT"
    else
        err
    fi
    return $rc
}

function test_max_rules() {
    title "Testing $TOTAL_COUNT rules $SKIP $NIC1 SMAC $SMAC DMAC $DMAC ACTION $ACTION"
    reset_tc $NIC1
    tc_batch1 "dev $NIC1" $TOTAL_COUNT
    echo "cleanup"
    time reset_tc $NIC1
}


if [ "$ACTION" == "mirred" ]; then
    ACTION="mirred egress redirect dev $NIC2"
elif [ "$ACTION" == "drop" ]; then
    :
else
    fail "Unknown action $ACTION"
fi

test_max_rules
test_done
