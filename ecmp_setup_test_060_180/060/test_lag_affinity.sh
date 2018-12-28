#!/bin/bash

HOST1="reg-r-vrt-020-060"
HOST1_PCI="0000:81:00.0"
HOST1_PORT1="ens1f0"
HOST1_PORT2="ens1f1"
HOST2="reg-r-vrt-020-180"
HOST2_PCI="0000:81:00.0"
HOST2_PORT1="ens2f0"
HOST2_PORT2="ens2f1"
SLEEP=2
TCPDUMP_FILTER="ip"


function cmd_on() {
	local host=$1
	shift
	local cmd=$@
	echo "[$host] $cmd"
	ssh $host -C "$cmd"
}

function kmsg() {
    local m=$@
    echo $m >> /dev/kmsg
    echo $m
}

function error() {
    local m=$@
    kmsg $m
    i=0 && mlxdump -d 81:00.0 fsdump --type FT --gvmi=$i  --no_zero=1 > /tmp/port$i
    i=1 && mlxdump -d 81:00.0 fsdump --type FT --gvmi=$i  --no_zero=1 > /tmp/port$i
#    killall iperf ; killall iperf
    exit 1
}

function restore_link() {
        echo -e "\n\n"
	kmsg "restore ports"
	cmd_on $HOST1 ifconfig $HOST1_PORT1 up
	cmd_on $HOST1 ifconfig $HOST1_PORT2 up

	cmd_on $HOST2 ifconfig $HOST2_PORT1 up
	cmd_on $HOST2 ifconfig $HOST2_PORT2 up

        service openvswitch restart

        echo "route" ; ip r show 36.0.10.0/24
        route_update 0
        echo "route" ; ip r show 36.0.10.0/24

        kmsg "update affinity"
	cmd_on $HOST1 "echo 0 > /sys/kernel/debug/mlx5/$HOST1_PCI/lag_affinity"
	cmd_on $HOST2 "echo 0 > /sys/kernel/debug/mlx5/$HOST2_PCI/lag_affinity"
        ovs-dpctl dump-flows type=offloaded
	echo "sleep $SLEEP"
	sleep $SLEEP
        #echo "wait for rules"
        #wait_for_n
        sleep 4
        check_offloaded $HOST1_PORT1
        check_offloaded $HOST1_PORT2
}

function route_update() {
    local case=$1

    cmd="ip r change 36.0.10.0/24"

    if [ $case -eq 0 ]; then
        cmd+=" nexthop via 38.2.10.1 dev $HOST1_PORT1"
        cmd+=" nexthop via 38.1.10.1 dev $HOST1_PORT2"
    elif [ $case -eq 1 ]; then
        cmd+=" nexthop via 38.1.10.1 dev $HOST1_PORT2"
    elif [ $case -eq 2 ]; then
        cmd+=" nexthop via 38.2.10.1 dev $HOST1_PORT1"
    else
        echo "### base route case $case"
        exit 1
    fi

    kmsg "route update case $case"
    cmd_on $HOST1 $cmd

    if [ $? -ne 0 ]; then
        error "### ERROR route update"
    fi
}

function wait_for_n() {
    local max=5

    for i in `seq $max`; do
        ping -c 3 -w 1 -q 38.1.10.1 &>/dev/null
        ip n show 38.1.10.1 | grep -i REACHABLE
        if [ $? -eq 0 ]; then
            break
        fi
    done
    if [ $i -eq $max ]; then
        ip n
        error "### error waiting for neigh"
    fi

    for i in `seq $max`; do
        ping -c 3 -w 1 -q 38.2.10.1 &>/dev/null
        ip n show 38.2.10.1 | grep -i REACHABLE
        if [ $? -eq 0 ]; then
            break
        fi
    done
    if [ $i -eq $max ]; then
        ip n
        error "### error waiting for neigh"
    fi
}

function test1() {
        echo -e "\n\n"
	kmsg "port1 down"
	cmd_on $HOST1 ifconfig $HOST1_PORT1 down
	cmd_on $HOST2 ifconfig $HOST2_PORT1 down
        route_update 1
        kmsg "update affinity"
	cmd_on $HOST1 "echo 2 > /sys/kernel/debug/mlx5/$HOST1_PCI/lag_affinity"
	cmd_on $HOST2 "echo 2 > /sys/kernel/debug/mlx5/$HOST2_PCI/lag_affinity"
        ovs-dpctl dump-flows type=offloaded
	echo "sleep $SLEEP"
	sleep $SLEEP
        check_traffic $HOST1_PORT2
        check_offloaded $HOST1_PORT2

        restore_link

        echo -e "\n\n"
	kmsg "port2 down"
	cmd_on $HOST1 ifconfig $HOST1_PORT2 down
	cmd_on $HOST2 ifconfig $HOST2_PORT2 down
        route_update 2
        kmsg "update affinity"
	cmd_on $HOST1 "echo 1 > /sys/kernel/debug/mlx5/$HOST1_PCI/lag_affinity"
	cmd_on $HOST2 "echo 1 > /sys/kernel/debug/mlx5/$HOST2_PCI/lag_affinity"
        ovs-dpctl dump-flows type=offloaded
	echo "sleep $SLEEP"
	sleep $SLEEP
        check_traffic $HOST1_PORT1
        check_offloaded $HOST1_PORT1

        restore_link
}

function check_traffic() {
    local dev=$1

    ip r show 36.0.10.0/24
    if [ $? -ne 0 ]; then
        error "### ERROR Missing route"
    fi

    local a=`ethtool -S $dev | grep rx_bytes_phy: | awk {'print $2'}`
    sleep 1
    local b=`ethtool -S $dev | grep rx_bytes_phy: | awk {'print $2'}`
    local c=`bc<<<$b-$a`
    if [ $c -lt 10000 ]; then
        error "### ERROR no traffic ($c)"
    fi
}

function check_offloaded() {
    local dev=$1
    timeout 1 tcpdump -nnepi $dev -c 10 "$TCPDUMP_FILTER" &
    tpid1=$!

    wait $tpid1 && error "### `date` ERROR not offloaded on port $HOST1_PORT1"
}


restore_link
for i in `seq 100`; do
	test1
done
killall iperf ; killall iperf
echo "done"
