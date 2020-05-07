#!/bin/bash
#
# Test reload of mlx5 core module while deleting tc flows from userspace
# 1. add many tc rules
# 2. start reload of mlx5 core module in the background
# 3. start deleting tc rules
#
# Expected result: not to crash
#
# Bug SW #1481373: [upstream] Flow table wasn't destroyed, refcount > 1
#

NIC=${1:-ens5f0}
COUNT=500

my_dir="$(dirname "$0")"
. $my_dir/common.sh

enable_switchdev
rep=`get_rep 0`
if [ -z "$rep" ]; then
    fail "Missing rep $rep"
    exit 1
fi
reset_tc $NIC
reset_tc $rep


title "add $COUNT rules"
for i in `seq $COUNT`; do
    num1=`printf "%02x" $((i / 100))`
    num2=`printf "%02x" $((i % 100))`
    tc filter add dev $rep protocol ip parent ffff: prio 1 handle $i \
        flower skip_sw \
        src_mac e1:22:33:44:${num1}:$num2 \
        dst_mac e2:22:33:44:${num1}:$num2 \
        action drop || fail "Failed to add rule"
done

function del_rules() {
    local first=true
    for i in `seq $COUNT`; do
        num1=`printf "%02x" $((i / 100))`
        num2=`printf "%02x" $((i % 100))`
        tc filter del dev $rep protocol ip parent ffff: prio 1 handle $i flower
        if [ "$?" != 0 ]; then
            if [ $first = true ]; then
                fail "Failed to del first rule"
            fi
            break
        fi
        first=false
    done
}


title "test reload modules"
reload_modules &
reload_modules_pid=$!
# with cx5 we tested 1 second but with cx4 device already gone so decreased the
# sleep from 1 second to have first rule add and then cleanup start.
sleep 0.2
title "del $COUNT rules"
del_rules
sleep 5
reset_tc $rep
wait $reload_modules_pid
if [ $? != 0 ]; then
  load_modules
  fail "TEST FAILED"
fi
test_done
