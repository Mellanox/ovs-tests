#!/bin/bash
#
# Reported traffic not working from IBM
# Paul debug result: link down/up overflow the sqn to loop around as fw use 32
# bits but driver used 16 bits.

my_dir="$(dirname "$0")"
. $my_dir/common.sh

config_sriov 2
enable_switchdev_if_no_rep $REP

channels=24
ethtool -L $NIC combined $channels

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

# check source_sqn for rules with destination uplink
i=0 && mlxdump -d $PCI fsdump --type FT --gvmi=$i --no_zero > /tmp/port$i || err "mlxdump failed"
cat /tmp/port0 | grep "dest.*0xfff" -B 1 | grep sqn | tail -4

title "Check packets"
ifconfig $NIC 2.2.2.2/24
ip n r 2.2.2.3 dev $NIC lladdr e4:11:56:26:52:11

ethtool -S $NIC | grep tx_packets
phy1=`ethtool -S $NIC | grep tx_packets_phy | cut -d: -f2`

ping -q -c 50 -i 0.01 -W 2 2.2.2.3

ethtool -S $NIC | grep tx_packets
phy2=`ethtool -S $NIC | grep tx_packets_phy | cut -d: -f2`

((phy1+=10))
if [ $phy1 -gt $phy2 ]; then
    err "Packets didn't go to wire"
fi

ifconfig $NIC 0

test_done
