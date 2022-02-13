#!/bin/bash
#
# Test rule with multiple ct clear actions which are redundant
#
# The bug is the driver handling ct_clear again and again adding the same
# mod hdr action to reset reg_c but are a waste and eventually wasting all resources.
#
# [Kernel Upstream] Bug SW #2959609: Some rule are not offloaded to HW in OVN K8s Pod 2 External use case

my_dir="$(dirname "$0")"
. $my_dir/common.sh

config_sriov
enable_switchdev

reset_tc $NIC

title "Test many ct clear acts"
# Error: mlx5_core: Failed to set registers for ct clear.
tc_filter add dev $NIC ingress protocol ip prio 2 flower skip_sw verbose \
    action ct clear ct clear ct clear ct clear pipe ct clear ct clear pipe drop

title "Test ct clear acts + pedits"
# Error: mlx5_core: can't offload re-write of non TCP/UDP.
tc_filter add dev $NIC ingress protocol ip prio 3 flower ip_proto tcp skip_sw verbose \
    action ct clear ct clear ct clear ct clear pipe \
           pedit ex munge ip ttl add 0xff \
                    munge ip dst set 7.7.7.2 \
                    munge ip src set 7.7.7.1 \
                    munge eth src set aa:ba:cc:dd:ee:fe \
                    munge eth dst set aa:b7:cc:dd:ee:fe pipe \
                    mirred egress redirect dev $REP

reset_tc $NIC
test_done
