#!/bin/bash
#
# Test reload of mlx5 core module while adding tc flows from userspace
# 2. start reload of mlx5 core module in the background
# 3. start adding tc rules
# 4. reset tc
#
# Expected result: not to crash
#

COUNT=500

my_dir="$(dirname "$0")"
. $my_dir/common.sh

enable_switchdev
require_interfaces REP
reset_tc $REP


function add_rules() {
    local first=true
    for i in `seq $COUNT`; do
        num1=`printf "%02x" $((i / 100))`
        num2=`printf "%02x" $((i % 100))`
        tc filter add dev $REP protocol ip parent ffff: prio 1 \
            flower skip_sw \
            src_mac e1:22:33:44:${num1}:$num2 \
            dst_mac e2:22:33:44:${num1}:$num2 \
            action drop 2>/dev/null
        if [ "$?" != 0 ]; then
            if [ $first = true ]; then
                err "Failed to add first rule"
            fi
            break
        fi
        first=false
    done
}


title "test reload modules"
start_check_syndrome

title "add $COUNT rules"
add_rules &
sleep 1
reload_modules &
reload_modules_pid=$!
wait $reload_modules_pid
reload_modules_result=$?

check_syndrome
[ -e /sys/class/net/$REP ] && reset_tc $REP

if [ $reload_modules_result != 0 ]; then
  load_modules
fi
test_done
