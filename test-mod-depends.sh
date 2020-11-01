#!/bin/bash
#
# Verify mlx5_core has only expected module dependencies
# i.e. not dependent on act_ct or nf_flow_table
#
#  #2188070: [CT offload] [mlx5] always depend on act_ct/flow_table, which pulls conntrack

my_dir="$(dirname "$0")"
. $my_dir/common.sh


function run() {
    title "Look for unexpected mlx5_core dependent modules"

    local from_ofed="devlink|mlx_compat|mdev|memtrack"
    local expected="ptp|tls|mlxfw|pci_hyperv_intf|$from_ofed|nf_conntrack"
    local dependent=`lsmod | grep mlx5_core | grep -v ^mlx5_core | awk {'print $1'} | grep -vE -w "$expected" | xargs echo`

    if [ -n "$dependent" ]; then
        err "Found dependent modules: $dependent"
        return
    fi

    success
}


run
test_done
