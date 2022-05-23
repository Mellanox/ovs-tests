#!/bin/bash

MACSEC_IF="macsec0"
TX_SA="0"
RX_SA="0"
TX_ID="00"
RX_ID="00"
SCI="1"
RX_SCI="2"
TX_SA_STATE="on"
PACKET_NUMBER="1"
MACSEC_IP_CLIENT="2.2.2.1/24"
MACSEC_IP_SERVER="2.2.2.2/24"
DEV_IP_CLIENT="1.1.1.1/24"
DEV_IP_SERVER="1.1.1.2/24"
CUSTOM_DEV_IP=""
CUSTOM_MACSEC_IP=""
CIPHER=""
ICVLEN=""
ENCRYPT=""
SEND_SCI=""
END_STATION=""
SCB=""
PROTECT=""
REPLAY=""
WINDOW=""
VALIDATE=""
ENCODINGSA=""
SET_ENCODINGSA=""
TX_SA_TO_ENABLE=""

#Keys
LOCAL_KEY="dffafc8d7b9a43d5b9a3dfbbf6a30c16"
REMOTE_KEY="ead3664f508eb06c40ac7104cdae4ce5"
LOCAL_KEY_256="f8c0b084e8f98d0d9b73f7f6a91e01b107c61c283f04bf931401959db69d6150"
REMOTE_KEY_256="e95e4ece4d7584a43e65c445dbc0281183a7cc71c873b066a75b72251beb9080"
MULTI_LOCAL_KEY="dffafc8d7b9a43d5b9a3dfbbf6a30c1"
MULTI_REMOTE_KEY="ead3664f508eb06c40ac7104cdae4ce"
MULTI_LOCAL_KEY_256="f8c0b084e8f98d0d9b73f7f6a91e01b107c61c283f04bf931401959db69d615"
MULTI_REMOTE_KEY_256="e95e4ece4d7584a43e65c445dbc0281183a7cc71c873b066a75b72251beb908"

function configure_device() {
    ip address flush $DEVICE
    if [ "$SIDE" == "server" ]; then
        ip address add $DEV_IP_SERVER dev $DEVICE
        ifconfig $DEVICE up
    else
        ip address add $DEV_IP_CLIENT dev $DEVICE
        ifconfig $DEVICE up
    fi
}

function configure_macsec_interface() {
    ip link add link $DEVICE $MACSEC_IF type macsec sci $SCI $CIPHER $ICVLEN $ENCRYPT $SEND_SCI $END_STATION $SCB $PROTECT $REPLAY $WINDOW $VALIDATE $ENCODINGSA || exit 1
}

function configure_macsec_secrets() {
    ip macsec add $MACSEC_IF tx sa $TX_SA pn $PACKET_NUMBER $TX_SA_STATE key $TX_ID $TX_KEY

    ip macsec add $MACSEC_IF rx sci $RX_SCI on

    ip macsec add $MACSEC_IF rx sci $RX_SCI sa $RX_SA pn $PACKET_NUMBER on key $RX_ID $RX_KEY
}

function configure_macsec_multi_secrets() {
    local effective_local_key="$MULTI_LOCAL_KEY"
    local effective_remote_key="$MULTI_REMOTE_KEY"
    local i

    if [[ $CIPHER == "cipher gcm-aes-256"  || $CIPHER == "cipher gcm-aes-xpn-256" ]]; then
        effective_local_key="$MULTI_LOCAL_KEY_256"
        effective_remote_key="$MULTI_REMOTE_KEY_256"
    fi

    for i in 2 3 4
    do
        if [ "$SIDE" == "server" ]; then
            ip macsec add $MACSEC_IF tx sa $((i-1)) pn $PACKET_NUMBER off key "0$i" "$effective_remote_key$i"
        
            ip macsec add $MACSEC_IF rx sci $RX_SCI sa $((i-1)) pn $PACKET_NUMBER on key "0$i" "$effective_local_key$i"
        else
            ip macsec add $MACSEC_IF tx sa $((i-1)) pn $PACKET_NUMBER off key "0$i" "$effective_local_key$i"
        
            ip macsec add $MACSEC_IF rx sci $RX_SCI sa $((i-1)) pn $PACKET_NUMBER on key "0$i" "$effective_remote_key$i"
        fi
    done
}

function switch_tx_sa() {
    for i in 0 1 2 3
    do
        ip macsec set $MACSEC_IF tx sa $i off
    done
    ip macsec set $MACSEC_IF tx sa $TX_SA_TO_ENABLE on
}

function set_encodingsa() {
    ip link set link $DEVICE $MACSEC_IF type macsec encodingsa $SET_ENCODINGSA
}

function configure_macsec_ips() {
    if [ "$SIDE" == "server" ]; then
        ip address add $MACSEC_IP_SERVER dev $MACSEC_IF
        ifconfig $MACSEC_IF up
    else
        ip address add $MACSEC_IP_CLIENT dev $MACSEC_IF
        ifconfig $MACSEC_IF up
    fi
}

function offload_macsec() {
    ip macsec offload $MACSEC_IF mac
}

function cleanup_macsec() {
    ip link show | grep $MACSEC_IF > /dev/null && ip link del $MACSEC_IF 
}

function usage() {
    cat << HEREDOC

    Usage: `readlink -f "$0"` --device <device> [OPTION...]

    optional arguments:
        -h, --help           show this help message and exit
        --tx-key             <KEY> Use a specific key for tx sa
        --rx-key             <KEY> Use a specific key for rx sa
        --interface          Use a specific MACSec interface
        --pn                 <packet_number> , default is 1
        --sci                <sci> , default is 1 , this is the sci used for Tx SAs
        --rx-sci             <sci> , default is 2 , this is the sci used for Rx SAs
        --cipher             <default | gcm-aes-128 | gcm-aes-256 | gcm-aes-xpn-128 | gcm-aes-xpn-256>
        --icvlen             <icv length> , usually 8-16 bytes
        --tx-sa-state        <on|off>, default is on
        --encrypt            <on|off>
        --send-sci           <on|off>
        --end-station        <on|off>
        --scb                <on|off>
        --protect            <on|off>
        --replay             <on|off>
        --window             replay window size
        --validate           <strict|check|disabled>
        --encoding-sa        <0..3> , used for configuring macsec
        --set-encoding-sa    <0..3> , changes the encoding sa for an existing config,a device must be provided
                             and a macsec interface needs to be provided using --interface , if not provided
                             default interface will be used.
        --add-multi-sa       Adds 4 different SAs to the interface , provide other side SCI using --sci
        --side               <client|server> configuration side, default is client
        --offload            Enable mac offload
        -d, --delete         <MACSec interface> Delete a MACSec interface
        --dev-ip             Use a specific ip for the local device,
                            default ips - client 1.1.1.1 , server 1.1.1.2
                             you need to provide a subnet too, e.g 3.3.3.1/24

        --macsec-ip          Use a specific ip for the local macsec interface,
                             default ips - client 2.2.2.1 , server 2.2.2.2
                             you need to provide a subnet too, e.g 3.3.3.2/24

        --enable-sa          {0..3} , enables specific TX sa, macsec interface needs to be
                             provided using --interface , if not provided default interface will
                             be used. please dont use this flag with other flags here is a usage e.g:
                             `readlink -f "$0"` --interface macsec0 --enable-sa 2 --sci 2

HEREDOC

    exit $1
}

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --tx-key)
        TX_KEY="$2"
        shift # pass argument
        shift # pass value
        ;;
        --rx-key)
        RX_KEY="$2"
        shift # pass argument
        shift # pass value
        ;;
        --device)
        DEVICE="$2"
        shift # pass argument
        shift # pass value
        ;;
        --remote)
        REMOTE_IP="$2"
        shift # pass argument
        shift # pass value
        ;;
        --interface)
        MACSEC_IF="$2"
        shift # pass argument
        shift # pass value
        ;;
        --side)
        SIDE="$2"
        shift # pass argument
        shift # pass value
        ;;
        --dev-ip)
        CUSTOM_DEV_IP="$2"
        shift # pass argument
        shift # pass value
        ;;
        --macsec-ip)
        CUSTOM_MACSEC_IP="$2"
        shift # pass argument
        shift # pass value
        ;;
        --tx-sa-state)
        TX_SA_STATE="$2"
        shift # pass argument
        shift # pass value
        ;;
        --enable-sa)
        TX_SA_TO_ENABLE="$2"
        shift # pass argument
        shift # pass value
        ;;
        --offload)
        OFFLOAD="1"
        shift # pass argument
        ;;
        --add-multi-sa)
        MULTI_SA="1"
        shift # pass argument
        ;;
        -d | --delete)
        IF_TO_DELETE="$2"
        shift # pass argument
        shift # pass value
        ;;
        --cipher)
        CIPHER="cipher $2"
        shift # pass argument
        shift # pass value
        ;;
        --icvlen)
        ICVLEN="icvlen $2"
        shift # pass argument
        shift # pass value
        ;;
        --encrypt)
        ENCRYPT="encrypt $2"
        shift # pass argument
	shift #pass value
        ;;
        --send-sci)
        SEND_SCI="send_sci $2"
        shift # pass argument
        shift # pass value
        ;;
        --end-station)
        END_STATION="end_station $2"
        shift # pass argument
        shift # pass value
        ;;
        --scb)
        SCB="scb $2"
        shift # pass argument
        shift # pass value
        ;;
        --protect)
        PROTECT="protect $2"
        shift # pass argument
        shift # pass value
        ;;
        --replay)
        REPLAY="replay $2"
        shift # pass argument
        shift # pass value
        ;;
        --window)
        WINDOW="window $2"
        shift # pass argument
        shift # pass value
        ;;
        --validate)
        VALIDATE="validate $2"
        shift # pass argument
        shift # pass value
        ;;
        --encoding-sa)
        ENCODINGSA="encodingsa $2"
        TX_SA="$2"
        RX_SA="$2"
        shift # pass argument
        shift # pass value
        ;;
        --set-encoding-sa)
        SET_ENCODINGSA="$2"
        shift # pass argument
        shift # pass value
        ;;
        --pn)
        PACKET_NUMBER="$2"
        shift # pass argument
        shift # pass first value
        ;;
        --sci)
        SCI="$2"
        shift # pass argument
        shift # pass first value
        ;;
        --rx-sci)
        RX_SCI="$2"
        shift # pass argument
        shift # pass first value
        ;;
        -h | --help) # help option
        usage 0
        ;;
        *)    # unknown option
        usage 1
        ;;
    esac
done

if [[ "$IF_TO_DELETE" != "" ]]; then
    ip link del $IF_TO_DELETE
    exit 0
fi

if [[ "$TX_SA_TO_ENABLE" != "" ]]; then
    switch_tx_sa
    exit 0
fi

if [[ "$DEVICE" == "" ]]; then
    usage 1
fi

if [[ "$SET_ENCODINGSA" != "" ]]; then
    set_encodingsa
    exit 0
fi

#in case of KEYS not getting passed use default
if [[ $TX_KEY == "" ]]; then
    if [ "$SIDE" == "server" ]; then
        if [[ $CIPHER == "cipher gcm-aes-256"  || $CIPHER == "cipher gcm-aes-xpn-256" ]]; then
            TX_KEY="$REMOTE_KEY_256"
        else
            TX_KEY="$REMOTE_KEY"
	fi
    else
        if [[ $CIPHER == "cipher gcm-aes-256"  || $CIPHER == "cipher gcm-aes-xpn-256" ]]; then
            TX_KEY="$LOCAL_KEY_256"
        else
            TX_KEY="$LOCAL_KEY"
	fi
    fi
fi

if [[ $RX_KEY == "" ]]; then
    if [ "$SIDE" == "server" ]; then
        if [[ $CIPHER == "cipher gcm-aes-256"  || $CIPHER == "cipher gcm-aes-xpn-256" ]]; then
            RX_KEY="$LOCAL_KEY_256"
        else
            RX_KEY="$LOCAL_KEY"
	fi
    else
        if [[ $CIPHER == "cipher gcm-aes-256"  || $CIPHER == "cipher gcm-aes-xpn-256" ]]; then
            RX_KEY="$REMOTE_KEY_256"
        else
            RX_KEY="$REMOTE_KEY"
	fi
    fi
fi

#check for any custom IPS
if [[ $CUSTOM_DEV_IP != "" ]]; then
    if [ "$SIDE" == "server" ]; then
        DEV_IP_SERVER="$CUSTOM_DEV_IP"
    else
        DEV_IP_CLIENT="$CUSTOM_DEV_IP"
    fi
fi

if [[ $CUSTOM_MACSEC_IP != "" ]]; then
    if [ "$SIDE" == "server" ]; then
        MACSEC_IP_SERVER="$CUSTOM_MACSEC_IP"
    else
        MACSEC_IP_CLIENT="$CUSTOM_MACSEC_IP"
    fi
fi

#if we are using the default RX_SCI and SCI and we are on server side then revert the SCIs
if [[ $RX_SCI == "2" && $SCI == "1" && $SIDE == "server" ]]; then
    RX_SCI=1
    SCI=2
fi

#delete macsec if exists
cleanup_macsec

#bring up the device and configure ips
configure_device

#check if device exists, add it otherwise
configure_macsec_interface

#Enable offload if requested
if [ "$OFFLOAD" == 1 ]; then
    offload_macsec
fi

configure_macsec_secrets

configure_macsec_ips

#Configure max number of SAs if requested
if [ "$MULTI_SA" == 1 ]; then
    configure_macsec_multi_secrets
fi
