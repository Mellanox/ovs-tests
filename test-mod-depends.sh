#!/bin/bash
#
# Verify mlx5_core has only expected module dependencies
# i.e. not dependent on act_ct or nf_flow_table
#
#  #2188070: [CT offload] [mlx5] always depend on act_ct/flow_table, which pulls conntrack

my_dir="$(dirname "$0")"
. $my_dir/common.sh


function run() {
    title "Check for unexpected mlx5_core module dependencies"

    local from_ofed="devlink|mlx_compat|mdev|memtrack"
    local expected="ptp|tls|mlxfw|pci-hyperv-intf|$from_ofed"
    local dependent=`modinfo -F depends mlx5_core | tr ',' '\n' | grep -vE -w "$expected" | xargs echo`

    modinfo -F depends mlx5_core

    if [ -n "$dependent" ]; then
        err "Unexpected module dependencies: $dependent"
        return
    fi

    success
}


run
test_done
