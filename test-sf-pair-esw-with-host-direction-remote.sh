#!/bin/bash
#
# Test host direction SF fast path traffic from SF to VF.


my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-sf.sh

IP1="7.7.7.1"
IP2="7.7.7.2"

function cleanup() {
    log "cleanup"
    reset_tc $REP

    local i sfs
    ip netns ls | grep -q ns0 && sfs=`ip netns exec ns0 devlink dev | grep -w sf`
    for i in $sfs; do
        ip netns exec ns0 devlink dev reload $i netns 1
    done
    ip -all netns delete
    remove_sfs
}

trap cleanup EXIT

function set_sf_esw() {
    local i ids a sf port

    title "Set SF eswitch"

    # Failing to change fw with sf inactive but works with unbind.
    unbind_sfs
    for port in `get_all_sf_pci`; do
        port=${port%:}
        devlink_port_eswitch_enable $port
        devlink_port_show $port
    done
    bind_sfs

    fail_if_err

    for sf_dev in `get_aux_sf_devices`; do
        sf=`basename $sf_dev/net/*`
        echo "SF $sf phys_switch_id `cat $sf_dev/net/*/phys_switch_id`" || fail "Failed to get SF switch id"
    done
}

function verify_single_ib_device() {
    local expected=$1

    title "Verify single IB device with multiple ports"

    local sf_dev=`$SFCMD dev | grep -w sf | head -1`
    local sf_ib_dev=`basename /sys/bus/auxiliary/devices/$sf_dev/infiniband/*`
    rdma link show | grep -w $sf_ib_dev

    local count=`rdma link show | grep -w $sf_ib_dev | wc -l`

    if [ "$count" -ne $expected ]; then
        err "Expected $expected ports"
    else
        success
    fi
}

function config() {
    local count=$1
    local direction=${2:-""}

    title "Config"

    if [ -z $direction ]; then
        create_sfs $count
    elif [ "$direction" == "network" ]; then
        create_network_direction_sfs $count
    elif [ "$direction" == "host" ]; then
        create_host_direction_sfs $count
    elif [ "$direction" == "both" ]; then
        create_network_direction_sfs $count
        create_host_direction_sfs $count
        ((count+=count))
    fi

    set_sf_esw $count
    reload_sfs_into_ns
    set_sf_switchdev
    log "Wait for shared fdb wq"
    sleep 3
    verify_single_ib_device $((count*2))

    config_vf ns1 $VF $REP
}

function test_ping_single() {
    local id=$1
    local a sf sf_rep ip1 ip2
    local num=$((-1+$id))

    sf="eth$num"

    local reps=`sf_get_all_reps`
    sf_rep=$(echo $reps | cut -d" " -f$id)

    ip1="$id.$id.$id.1"
    ip2="$id.$id.$id.2"

    title "Verify ping SF$id $sf<->$VF"

    ip netns exec ns0 ifconfig $sf $ip1/24 up
    ip link set dev $sf_rep up
    ip netns exec ns1 ifconfig $VF $ip2/24 up

    reset_tc $REP $sf_rep
    tc_filter add dev $REP ingress protocol arp flower action mirred egress redirect dev $sf_rep
    tc_filter add dev $REP ingress protocol ip flower action mirred egress redirect dev $sf_rep
    tc_filter add dev $sf_rep ingress protocol arp flower action mirred egress redirect dev $REP
    tc_filter add dev $sf_rep ingress protocol ip flower action mirred egress redirect dev $REP

    ip netns exec ns0 ping -w 2 -c 1 $ip2 && success || err "Ping failed for SF$id $sf<->$REP"
    reset_tc $REP $sf_rep
}

function test_ping() {
    local count=$1
    local i

    for i in `seq $count`; do
        test_ping_single $i
    done
}

config_sriov 2
enable_switchdev
bind_vfs
test_count=2

cleanup
config $test_count "host"
test_ping $test_count

trap - EXIT
cleanup
test_done
