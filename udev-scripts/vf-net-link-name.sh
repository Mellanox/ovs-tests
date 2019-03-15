#!/bin/bash

SWID=$1
# might be pf0vf1 so only get vf number
PORT=${2##*f}
PORT_UPLINK="65534"
PORT_UPLINK0="p0"
PORT_UPLINK1="p1"

if [ "$PORT" = "$PORT_UPLINK0" ] || [ "$PORT" = "$PORT_UPLINK1" ]; then
    # sometimes we don't have ID_NET_NAME but have SLOT (rhel 7.2) or PATH (rhel 7.6).
    if [ -z "$ID_NET_NAME" ]; then
	if [ -n "$ID_NET_NAME_SLOT" ]; then
	    ID_NET_NAME=$ID_NET_NAME_SLOT
	elif [ -n "$ID_NET_NAME_PATH" ]; then
            ID_NET_NAME=$ID_NET_NAME_PATH
	fi
    fi
    if [ -n "$ID_NET_NAME" ]; then
        n=${ID_NET_NAME##*n}
	if [ "$n" = "$PORT_UPLINK0" ] || [ "$n" = "$PORT_UPLINK1" ]; then
            # strip n*
            NAME=${ID_NET_NAME%n*}
        else
            NAME=$ID_NET_NAME
        fi
        echo "NAME=$NAME"
    fi
    exit
fi

if [ "$PORT" = "$PORT_UPLINK" ]; then
    if [ -n "$ID_NET_NAME" ]; then
        NAME=${ID_NET_NAME%n$PORT_UPLINK}
        echo "NAME=$NAME"
    fi
    exit
fi

# WA to make sure uplink port is renamed first
sleep 0.5
for i in `ls -1 /sys/class/net/*/address`; do
    nic=`echo $i | cut -d/ -f 5`
    address=`cat $i | tr -d :`
    if [ "$address" = "$SWID" ]; then
        echo "NAME=${nic}_$PORT"
        break
    fi
done
