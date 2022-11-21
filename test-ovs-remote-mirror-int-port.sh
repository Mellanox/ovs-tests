#!/bin/bash
#
#
# Test ovs setting with internal port but the driver should not support
# internal port (i.e. cx5) so the driver can offload over stack device.
#
# [MKT. MLNX_OFED] Feature Request #3055876: Remote Mirror over Vxlan or GRE tunnels are not
# offloaded in both directions when SMFS flow steering is enabled.
#
# Require external server

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_remote_server

IP=1.1.1.6
REMOTE=1.1.1.7

LOCAL_TUN=7.7.7.7
REMOTE_IP=7.7.7.8
VXLAN_ID=42
vlan=20
vlandev=${REMOTE_NIC}.$vlan

config_sriov 2
enable_switchdev
require_interfaces REP NIC
unbind_vfs
bind_vfs


function cleanup_remote() {
    on_remote "ip a flush dev $REMOTE_NIC
               ip l del dev vxlan1 &>/dev/null
               ip l del dev $vlandev &>/dev/null"
}

function cleanup() {
    ovs_clear_bridges &>/dev/null
    ip a flush dev $NIC
    ip netns del ns0 &>/dev/null
    cleanup_remote
    sleep 0.5
}
trap cleanup EXIT

function config() {
    cleanup
    # WA SimX bug? interface not receiving traffic from tap device to down&up to fix it.
    for i in $NIC $VF $REP ; do
            ifconfig $i down
            ifconfig $i up
            reset_tc $i
    done

    ip netns add ns0
    ip link set dev $VF netns ns0
    ip netns exec ns0 ifconfig $VF $IP/24 up

    config_ovs
}

function config_ovs() {
    echo "Restarting OVS"
    start_clean_openvswitch

    ovs-vsctl add-br br-phy
    ovs-vsctl add-port br-phy $NIC
    ovs-vsctl add-br br-int
    ovs-vsctl add-port br-int $REP
    ovs-vsctl                           \
	    -- add-port br-int br-int-patch \
	    -- set interface br-int-patch type=patch options:peer=br-phy-patch  \
	    -- add-port br-phy br-phy-patch       \
	    -- set interface br-phy-patch type=patch options:peer=br-int-patch  \

    # Setting the internal port as the tunnel underlay interface #
    ifconfig br-phy $LOCAL_TUN/24 up
    ifconfig br-phy up
    ovs-ofctl add-flow br-int "in_port=$REP, action=output:br-int-patch"
    ovs-ofctl add-flow br-int "in_port=br-int-patch, action=output:$REP"
    ovs-ofctl add-flow br-phy "in_port=br-phy-patch, action=push_vlan:0x8100,mod_vlan_vid:$vlan,output:$NIC" -O OpenFlow11
    ovs-ofctl add-flow br-phy "in_port=$NIC, dl_vlan=$vlan  action=pop_vlan,output:br-phy-patch"
    ovs-ofctl add-flow br-phy "in_port=$NIC, priority:2 action=output:br-phy"
    ovs-ofctl add-flow br-phy "in_port=br-phy  action=output:$NIC"
    ovs-vsctl add-port br-int vxlan2 -- set interface vxlan2 type=vxlan \
            options:local_ip=$LOCAL_TUN options:remote_ip=$REMOTE_IP \
            options:key=$VXLAN_ID options:dst_port=4789
    ovs-vsctl -- --id=@p1 get port $REP -- --id=@p2 get port vxlan2 -- \
	         --id=@m create mirror name=m1 select_src_port=@p1 select_dst_port=@p1 \
                 output-port=@p2 -- set bridge br-int mirrors=@m

}

function config_remote() {
    on_remote "ip link add link $REMOTE_NIC name $vlandev type vlan id 20
               ip link del vxlan1 &>/dev/null
               ip link add vxlan1 type vxlan id $VXLAN_ID dev $vlandev dstport 4789
               ip a flush dev $vlandev
               ip a add $REMOTE/24 dev $vlandev
               ip a add $REMOTE_IP/24 dev $REMOTE_NIC
               ip l set dev vxlan1 up
               ip l set dev $REMOTE_NIC up
               ip l set dev $vlandev up"
}

function run() {
    config
    config_remote

    sleep 2
    title "test ping"
    ip netns exec ns0 ping -q -c 1 -w 1 $REMOTE
    if [ $? -ne 0 ]; then
        err "ping failed"
        return
    fi

    title "test traffic"
    t=15
    on_remote timeout $((t+2)) iperf3 -s -D
    sleep 1
    ip netns exec ns0 timeout $((t+2)) iperf3 -c $REMOTE -t $t -P3 &
    pid2=$!

    # verify pid
    sleep 2
    kill -0 $pid2 &>/dev/null
    if [ $? -ne 0 ]; then
        err "iperf failed"
        return
    fi

    timeout $((t-4)) ip netns exec ns0 tcpdump -qnnei $VF -c 60 'tcp' &
    tpid1=$!
    timeout $((t-4)) tcpdump -qnnei $REP -c 10 'tcp' &
    tpid2=$!

    sleep $t
    title "Verify traffic on $VF"
    verify_have_traffic $tpid1
    title "Verify offload on $REP"
    verify_no_traffic $tpid2

    kill -9 $pid1 &>/dev/null
    on_remote killall -9 -q iperf3 &>/dev/null
    echo "wait for bgs"
    wait
}

run
trap - EXIT
cleanup
test_done
