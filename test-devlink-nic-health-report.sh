#!/bin/bash
#
# Test devlink dump nic health report
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


config_sriov 1 $NIC2
enable_legacy $NIC2

items=`devlink -j port show $NIC2 | jq '.port | to_entries[].key'`
if [ -z "$items" ] || [ "$items" == "null" ]; then
    fail "Cannot find devlink port for $NIC2"
fi

for item in $items ; do
    title "Check health reporters for $item"
    for report in tx rx; do
        tmp=`devlink -j health | jq ".health[$item][] | select(.reporter == \"$report\")"`
        if [ -z "$tmp" ]; then
            err "Missing devlink $report reporter for $item"
            continue
        fi
    done
done

config_sriov 0 $NIC2
test_done
