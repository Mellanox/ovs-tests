#!/bin/bash

SWID=$1
# might be pf0vf1 so only get vf number
PORT=${2##*f}
PORT_NAME=$2

is_bf=`lspci -s 00:00.0 2> /dev/null | grep -wq "PCI bridge: Mellanox Technologies" && echo 1 || echo 0`
if [ $is_bf -eq 1 ]; then
    echo NAME=${2/vf-1/hpf}
    exit 0
fi

# for pf and uplink rep fall to slot or path.
if [ -n "$ID_NET_NAME_SLOT" ]; then
    echo NAME="${ID_NET_NAME_SLOT%%np[[:digit:]]}"
fi

if [ -n "$ID_NET_NAME_PATH" ]; then
    echo NAME="${ID_NET_NAME_PATH%%np[[:digit:]]}"
fi

if [ -n "$NAME" ]; then
    NAME=`echo $NAME | sed 's/npf.vf/_/'`
    NAME=`echo $NAME | sed 's/np.v/v/'`
    echo NAME=$NAME
    exit
fi

function get_name() {
    local a=`udevadm info -q property -p /sys/class/net/$1 | grep $2 | cut -d= -f2`
    echo ${a%%np[[:digit:]]}
}

# for vf rep get parent slot/path.
parent_phys_port_name=${PORT_NAME%vf*}
parent_phys_port_name=${parent_phys_port_name//pf}
((parent_phys_port_name&=0x7))
parent_phys_port_name="p$parent_phys_port_name"
# try at most two times
for cnt in {1..2}; do
    for i in `ls -1 /sys/class/net/*/phys_switch_id`; do
        nic=`echo $i | cut -d/ -f 5`
        _swid=`cat $i`
        _portname=`cat /sys/class/net/$nic/phys_port_name`
        if [ -z $_portname ]; then
            # no uplink rep so no phys port name
            _portname=$parent_phys_port_name
        fi
        if [ "$_swid" = "$SWID" ] && [ "$_portname" = "$parent_phys_port_name" ]
        then
            parent_path=`get_name $nic ID_NET_NAME_SLOT`
            if [ -z "$parent_path" ]; then
                parent_path=`get_name $nic ID_NET_NAME_PATH`
            fi
            echo "NAME=${parent_path}_$PORT"
            exit
        fi
    done

    # swid changes when entering lag mode.
    # So if we didn't find current swid, get the updated one.
    SWID=`cat /sys/class/net/$INTERFACE/phys_switch_id`
done
