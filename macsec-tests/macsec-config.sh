#!/bin/bash

MACSEC_IF="macsec0"
VLAN_IF="macsec_vlan"
VLAN_ID="1"
TX_SA="0"
RX_SA="0"
TX_ID="00"
RX_ID="00"
TX_SA_STATE="on"
RX_SA_STATE="on"
PACKET_NUMBER="1"
MACSEC_IP_CLIENT="2.2.2.1/24"
MACSEC_IP_SERVER="2.2.2.2/24"
VLAN_IP_CLIENT="3.3.3.1/24"
VLAN_IP_SERVER="3.3.3.2/24"
DEV_IP_CLIENT="1.1.1.1/24"
DEV_IP_SERVER="1.1.1.2/24"
ENCRYPT="encrypt on"
MACSEC_MAC_ADDRESS_CLIENT="00:11:22:33:44:66"
MACSEC_MAC_ADDRESS_SERVER="00:11:22:33:44:77"
VLAN_MAC_ADDRESS_CLIENT="00:11:22:33:44:88"
VLAN_MAC_ADDRESS_SERVER="00:11:22:33:44:99"

#Keys
LOCAL_KEY="dffafc8d7b9a43d5b9a3dfbbf6a30c16"
REMOTE_KEY="ead3664f508eb06c40ac7104cdae4ce5"
LOCAL_KEY_256="f8c0b084e8f98d0d9b73f7f6a91e01b107c61c283f04bf931401959db69d6150"
REMOTE_KEY_256="e95e4ece4d7584a43e65c445dbc0281183a7cc71c873b066a75b72251beb9080"
MULTI_LOCAL_KEY="dffafc8d7b9a43d5b9a3dfbbf6a30c1"
MULTI_REMOTE_KEY="ead3664f508eb06c40ac7104cdae4ce"
MULTI_LOCAL_KEY_256="f8c0b084e8f98d0d9b73f7f6a91e01b107c61c283f04bf931401959db69d615"
MULTI_REMOTE_KEY_256="e95e4ece4d7584a43e65c445dbc0281183a7cc71c873b066a75b72251beb908"

function ip() {
    if [ "$DEBUG" = on ]; then
       echo "+ ip $@"
    fi
    command ip $@
}

function configure_device() {
    local device=$1
    local client_ip=$2
    local server_ip=$3

    ip address flush $device
    if [ "$SIDE" == "server" ]; then
        ip address add $server_ip dev $device
        ip link set dev $device up
    else
        ip address add $client_ip dev $device
        ip link set dev $device up
    fi
}

function configure_mac_address() {
    local device=$1
    local mac_address=$2

    ip link set dev $device address $mac_address
}

function configure_macsec_interface() {
    if [ "$VLAN" == "outer" ]; then
        ip link add link $VLAN_IF $MACSEC_IF type macsec sci $SCI $CIPHER $ICVLEN $ENCRYPT $SEND_SCI $END_STATION $SCB $PROTECT $REPLAY $WINDOW $VALIDATE $ENCODINGSA || exit 1
    else
        ip link add link $DEVICE $MACSEC_IF type macsec sci $SCI $CIPHER $ICVLEN $ENCRYPT $SEND_SCI $END_STATION $SCB $PROTECT $REPLAY $WINDOW $VALIDATE $ENCODINGSA || exit 1
    fi

    if [ "$UNIQUE_MAC" == "on" ];then
        if [ "$SIDE" == "server" ]; then
            configure_mac_address $MACSEC_IF $MACSEC_MAC_ADDRESS_SERVER
        else
            configure_mac_address $MACSEC_IF $MACSEC_MAC_ADDRESS_CLIENT
        fi
    fi
}

function configure_macsec_secrets() {
    local pn_cmd="pn"
    local packet_number="$PACKET_NUMBER"

    if [[ "$XPN" == "on" ]];then
        pn_cmd="xpn"
    fi

    ip macsec add $MACSEC_IF tx sa $TX_SA $pn_cmd $packet_number $TX_SA_STATE $SALT $SSCI key $TX_ID $TX_KEY

    ip macsec add $MACSEC_IF rx sci $RX_SCI on

    ip macsec add $MACSEC_IF rx sci $RX_SCI sa $RX_SA $pn_cmd $packet_number $RX_SA_STATE $SALT $SSCI_RX key $RX_ID $RX_KEY
}

function configure_macsec_multi_secrets() {
    local effective_local_key="$MULTI_LOCAL_KEY"
    local effective_remote_key="$MULTI_REMOTE_KEY"
    local i
    local pn_cmd="pn"
    local packet_number="$PACKET_NUMBER"

    if [[ "$XPN" == "on" ]];then
        pn_cmd="xpn"
    fi

    if [[ $CIPHER == "cipher gcm-aes-256"  || $CIPHER == "cipher gcm-aes-xpn-256" ]]; then
        effective_local_key="$MULTI_LOCAL_KEY_256"
        effective_remote_key="$MULTI_REMOTE_KEY_256"
    fi

    for i in 2 3 4; do
        if [ "$SIDE" == "server" ]; then
            ip macsec add $MACSEC_IF tx sa $((i-1)) $pn_cmd $PACKET_NUMBER off $SALT $SSCI key "0$i" "$effective_remote_key$i"

            ip macsec add $MACSEC_IF rx sci $RX_SCI sa $((i-1)) $pn_cmd $PACKET_NUMBER on $SALT $SSCI_RX key "0$i" "$effective_local_key$i"
        else
            ip macsec add $MACSEC_IF tx sa $((i-1)) $pn_cmd $PACKET_NUMBER off $SALT $SSCI key "0$i" "$effective_local_key$i"

            ip macsec add $MACSEC_IF rx sci $RX_SCI sa $((i-1)) $pn_cmd $PACKET_NUMBER on $SALT $SSCI_RX key "0$i" "$effective_remote_key$i"
        fi
    done
}

function switch_tx_sa() {
    for i in 0 1 2 3; do
        ip macsec set $MACSEC_IF tx sa $i off
    done
    ip macsec set $MACSEC_IF tx sa $TX_SA_TO_ENABLE on
}

function set_encodingsa() {
    ip link set link $DEVICE $MACSEC_IF type macsec encodingsa $SET_ENCODINGSA
}

function configure_macsec_ips() {
    configure_device $MACSEC_IF $MACSEC_IP_CLIENT $MACSEC_IP_SERVER
}

function configure_vlan_ips() {
    if [[ "$VLAN" != "outer" && "$VLAN" != "inner" ]]; then
        return;
    fi
    configure_device $VLAN_IF $VLAN_IP_CLIENT $VLAN_IP_SERVER
}


function ip_macsec_offload() {
    ip macsec offload $MACSEC_IF mac
}

function cleanup() {
    ip link show | grep $MACSEC_IF > /dev/null && ip link del $MACSEC_IF
    ip link show | grep $VLAN_IF > /dev/null && ip link del $VLAN_IF
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
        --rx-sa-state        <on|off>, default is on
        --encrypt            <on|off>
        --send-sci           <on|off>
        --end-station        <on|off>
        --scb                <on|off>
        --protect            <on|off>
        --replay             <on|off>
        --xpn                <on|off>, use extended packet number, default is off
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
        --inner-vlan         Configure Macsec with vlan as an inner header
        --outer-vlan         Configure Macsec with vlan as an outer header
        --vlan-interface     Use a specific Vlan interface
        --vlan-id            Use a specific Vlan id, default is 1
        --unique-mac         Use a unique mac address for macsec and vlan interfaces.
        --dev-ip             Use a specific ip for the local device,
                             default ips - client 1.1.1.1 , server 1.1.1.2
                             you need to provide a subnet too, e.g 3.3.3.1/24

        --macsec-ip          Use a specific ip for the local macsec interface,
                             default ips - client 2.2.2.1 , server 2.2.2.2
                             you need to provide a subnet too, e.g 4.4.4.2/24
        --vlan-ip            Use a specific ip for the local macsec interface,
                             default ips - client 3.3.3.1 , server 3.3.3.2
                             you need to provide a subnet too, e.g 4.4.4.2/24

        --enable-sa          {0..3} , enables specific TX sa, macsec interface needs to be
                             provided using --interface , if not provided default interface will
                             be used. please dont use this flag with other flags here is a usage e.g:
                             `readlink -f "$0"` --interface macsec0 --enable-sa 2 --sci 2

        --debug              Print the commands

HEREDOC

    exit $1
}

function parse_args() {
    while [[ $# -gt 0 ]]; do
        key="$1"
        case $key in
            --tx-key)
            TX_KEY="$2"
            shift 2
            ;;
            --rx-key)
            RX_KEY="$2"
            shift 2
            ;;
            --device)
            DEVICE="$2"
            shift 2
            ;;
            --remote)
            REMOTE_IP="$2"
            shift 2
            ;;
            --interface)
            MACSEC_IF="$2"
            shift 2
            ;;
            --side)
            SIDE="$2"
            shift 2
            ;;
            --dev-ip)
            CUSTOM_DEV_IP="$2"
            shift 2
            ;;
            --macsec-ip)
            CUSTOM_MACSEC_IP="$2"
            shift 2
            ;;
            --vlan-ip)
            CUSTOM_VLAN_IP="$2"
            shift 2
            ;;
            --tx-sa-state)
            TX_SA_STATE="$2"
            shift 2
            ;;
            --rx-sa-state)
            RX_SA_STATE="$2"
            shift 2
            ;;
            --enable-sa)
            TX_SA_TO_ENABLE="$2"
            shift 2
            ;;
            --offload)
            OFFLOAD="on"
            shift
            ;;
            --unique-mac)
            UNIQUE_MAC="on"
            shift
            ;;
            --inner-vlan)
            VLAN="inner"
            shift
            ;;
            --vlan-interface)
            VLAN_IF="$2"
            shift 2
            ;;
            --vlan-id)
            VLAN_ID="$2"
            shift 2
            ;;
            --outer-vlan)
            VLAN="outer"
            shift
            ;;
            --debug)
            DEBUG="on"
            shift
            ;;
            --add-multi-sa)
            MULTI_SA="on"
            shift
            ;;
            -d | --delete)
            IF_TO_DELETE="$2"
            shift 2
            ;;
            --cipher)
            CIPHER="cipher $2"
            shift 2
            ;;
            --icvlen)
            ICVLEN="icvlen $2"
            shift 2
            ;;
            --encrypt)
            ENCRYPT="encrypt $2"
            shift 2
            ;;
            --xpn)
            XPN="$2"
            shift 2
            ;;
            --send-sci)
            SEND_SCI="send_sci $2"
            shift 2
            ;;
            --end-station)
            END_STATION="end_station $2"
            shift 2
            ;;
            --scb)
            SCB="scb $2"
            shift 2
            ;;
            --protect)
            PROTECT="protect $2"
            shift 2
            ;;
            --replay)
            REPLAY="replay $2"
            shift 2
            ;;
            --window)
            WINDOW="window $2"
            shift 2
            ;;
            --validate)
            VALIDATE="validate $2"
            shift 2
            ;;
            --encoding-sa)
            ENCODINGSA="encodingsa $2"
            TX_SA="$2"
            RX_SA="$2"
            shift 2
            ;;
            --set-encoding-sa)
            SET_ENCODINGSA="$2"
            shift 2
            ;;
            --pn)
            PACKET_NUMBER="$2"
            shift 2
            ;;
            --sci)
            SCI="$2"
            shift 2
            ;;
            --rx-sci)
            RX_SCI="$2"
            shift 2
            ;;
            --ssci)
            SSCI="ssci $2"
            shift 2
            ;;
            --rx-ssci)
            SSCI_RX="ssci $2"
            shift 2
            ;;
            -h | --help) # Help option
            usage 0
            ;;
            *)    # Unknown option
            usage 1
            ;;
        esac
    done
}

function check_xpn() {
    if [[ $CIPHER == "cipher gcm-aes-xpn-128"|| $CIPHER == "cipher gcm-aes-xpn-256" ]]; then
        XPN="on"
    fi

    if [[ $XPN == "on" ]]; then
        #In case cipher not provided use default
        if [[ "$CIPHER" == "" ]]; then
            CIPHER="cipher gcm-aes-xpn-128"
        elif [[ "$CIPHER" == "cipher gcm-aes-128" ]]; then
            CIPHER="cipher gcm-aes-xpn-128"
        elif [[ "$CIPHER" == "cipher gcm-aes-256" ]]; then
            CIPHER="cipher gcm-aes-xpn-256"
        fi

        #In case salt not provided use default
        if [[ "$SALT" == "" ]]; then
            SALT="salt fc8d7b9a43d5b9a3dfbbf6a3"
        fi

        #In case ssci not provided use default
        if [[ "$SSCI" == "" ]]; then
            SSCI="ssci 1"
        fi
    fi
}

function check_keys() {
    #In case of KEYS not getting passed use default
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
}

function check_ips() {
    #Check for any custom IPS
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

    if [[ $CUSTOM_VLAN_IP != "" ]]; then
        if [ "$SIDE" == "server" ]; then
            VLAN_IP_SERVER="$CUSTOM_VLAN_IP"
        else
            VLAN_IP_CLIENT="$CUSTOM_VLAN_IP"
        fi
    fi
}

function check_sci() {
    #If we are using the default RX_SCI and SCI and we are on server side then revert the SCIs
    if [[ $RX_SCI == "" ]]; then
        if [[ $SIDE = "server" ]]; then
            RX_SCI="1"
        else
            RX_SCI="2"
        fi
    fi

    if [[ $SCI == "" ]]; then
        if [[ $SIDE = "server" ]]; then
            SCI="2"
        else
            SCI="1"
        fi
    fi

    #If only SSCI is passed then use same SSCI for SSCI_RX
    if [[ "$SSCI" != "" && "$SSCI_RX" == "" ]]; then
            SSCI_RX=$SSCI
    fi

    #If on server swap ssci's
    if [[ "$SIDE" == "server" ]]; then
            tmp=$SSCI
            SSCI=$SSCI_RX
            SSCI_RX=$tmp
    fi
}

function configure_inner_vlan() {
    if [ "$VLAN" != "inner" ]; then
        return;
    fi

    ip link add link $MACSEC_IF name $VLAN_IF type vlan id $VLAN_ID

    if [ "$UNIQUE_MAC" == "on" ];then
        if [ "$SIDE" == "server" ]; then
            configure_mac_address $VLAN_IF $VLAN_MAC_ADDRESS_SERVER
        else
            configure_mac_address $VLAN_IF $VLAN_MAC_ADDRESS_CLIENT
        fi
    fi
}

function configure_outer_vlan() {
    if [ "$VLAN" != "outer" ]; then
        return;
    fi

    ip link add link $DEVICE name $VLAN_IF type vlan id $VLAN_ID

    if [ "$UNIQUE_MAC" == "on" ];then
        if [ "$SIDE" == "server" ]; then
            configure_mac_address $VLAN_IF $VLAN_MAC_ADDRESS_SERVER
        else
            configure_mac_address $VLAN_IF $VLAN_MAC_ADDRESS_CLIENT
        fi
    fi
}

function main() {
    parse_args "$@"

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

    #Check for extended packet number
    check_xpn
    #Check if to use default keys
    check_keys
    #Check if to use default IPs
    check_ips
    #Check if to use default secure channel IDs
    check_sci
    #Delete interfaces if exist
    cleanup
    #Outer vlan
    configure_outer_vlan
    #Bring up the device and configure ips
    configure_device $DEVICE $DEV_IP_CLIENT $DEV_IP_SERVER
    #Check if device exists, add it otherwise
    configure_macsec_interface
    #Enable offload if requested
    if [ "$OFFLOAD" == "on" ]; then
        ip_macsec_offload
    fi

    configure_macsec_secrets

    #Bring up the macsec device and configure ips
    configure_macsec_ips

    #Configure max number of SAs if requested
    if [ "$MULTI_SA" == "on" ]; then
        configure_macsec_multi_secrets
    fi

    #Inner vlan
    configure_inner_vlan

    #Bring up the vlan device and configure ips
    configure_vlan_ips
}

main "$@"
