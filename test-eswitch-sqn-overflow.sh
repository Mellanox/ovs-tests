#!/bin/bash
#
# Reported traffic not working
# Paul debug result: link down/up overflow the sqn to loop around as fw use 32
# bits but driver used 16 bits.

my_dir="$(dirname "$0")"
. $my_dir/common.sh

config_sriov 2
enable_switchdev

max_ch=$(ethtool -l $NIC | grep Combined | head -1 | cut -f2-)
channels=24
if [ $max_ch -lt $channels ]; then
    channels=$max_ch
fi
ethtool -L $NIC combined $channels || fail "Failed to set $NIC channels to $channels"

# we 4 increaments in sqn per down/up.
jumps=4

needed=`echo 65535/$channels/$jumps+1|bc`

title "Link down/up $needed times"
for i in `seq $needed`; do
    ip link set dev $NIC down
    ip link set dev $NIC up
    ((tmp=i%50))
    [ $tmp -eq 0 ] && echo -n .
done
echo

mode=`get_flow_steering_mode $NIC`
if [ "$mode" == "dmfs" ]; then
    # check source_sqn for rules with destination uplink
    i=0 && mlxdump -d $PCI fsdump --type FT --gvmi=$i --no_zero > /tmp/port$i || err "mlxdump failed"
    cat /tmp/port0 | grep "dest.*0xfff" -B 1 | grep sqn | tail -4
fi

function check_packets() {
    title "Check packets"
    ifconfig $NIC 2.2.2.2/24
    ip n r 2.2.2.3 dev $NIC lladdr e4:11:56:26:52:11
    get_tx_pkts $NIC

    phy1=`get_tx_pkts $NIC`
    if [ -z "$phy1" ]; then
        err "Cannot get tx_packets_phy"
        return 1
    fi

    ping -q -c 50 -i 0.01 -W 2 2.2.2.3

    phy2=`get_tx_pkts $NIC`
    ((phy1+=10))
    if [ $phy1 -gt $phy2 ]; then
        err "Packets didn't go to wire"
    fi
}

check_packets
ifconfig $NIC 0
test_done
