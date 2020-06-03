#!/bin/bash

if [ "$ID_NET_DRIVER" != "mlx5_core" ]; then
    echo NAME=${ID_NET_NAME}
    exit 0
fi

if [ -n "$ID_NET_NAME_SLOT" ]; then
    NAME=$ID_NET_NAME_SLOT
elif [ -n "$ID_NET_NAME_PATH" ]; then
    NAME=$ID_NET_NAME_PATH
else
    NAME=${ID_NET_NAME}
fi

# WA Strip invalid chars. kernel 5.2.0 shows invalid characters in ID_NET_NAME_PATH
NAME=`echo $NAME | tr -cd '[:alnum:]._-'`

NAME=${NAME%%np[[:digit:]]}
# strip npX even from middle of the name.
# e.g. new kernels have vf name as ens0f0np1vf0
NAME=`echo $NAME | sed 's/np[0-9]\+vf/vf/'`
echo NAME=$NAME
exit 0
