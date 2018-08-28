#!/bin/bash
#
# Test to reproduce possible deadlock with flow groups.
#
# Bug SW #1486319: [Upstream] possible recursive locking detected when adding fwd and drop rules while traffic is going
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

enable_switchdev_if_no_rep $REP
set_eswitch_inline_mode_transport


function add_diff_mask_rules() {
    local key=${1:-25}
    tc filter add dev $REP parent ffff: protocol ip flower dst_mac e4:1d:2d:5d:$key:35 action drop
    tc filter add dev $REP parent ffff: protocol ip flower dst_mac e4:1d:2d:5d:$key:35 src_mac e4:1d:2d:5d:$key:36 action drop
    tc filter add dev $REP parent ffff: protocol ip flower dst_mac e4:1d:2d:5d:$key:35 ip_proto udp dst_port 99 action drop
    tc filter add dev $REP parent ffff: protocol ip flower dst_mac e4:1d:2d:5d:$key:35 ip_proto udp src_port 99 action drop
    tc filter add dev $REP parent ffff: protocol ip flower dst_mac e4:1d:2d:5d:$key:35 ip_proto tcp dst_port 99 action drop
    tc filter add dev $REP parent ffff: protocol ip flower dst_mac e4:1d:2d:5d:$key:35 ip_proto tcp src_port 99 action drop
    tc filter add dev $REP parent ffff: protocol ip flower dst_mac e4:1d:2d:5d:$key:35 src_ip 1.1.1.1 action drop
    tc filter add dev $REP parent ffff: protocol ip flower dst_mac e4:1d:2d:5d:$key:35 dst_ip 1.1.1.1 action drop
}


title "Test flow groups possible lock issue"
start_check_syndrome
reset_tc_nic $REP

for i in `seq 5`; do
    echo "phase$i"
    add_diff_mask_rules $i
done

reset_tc_nic $REP
check_syndrome
test_done
