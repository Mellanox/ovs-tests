function devlink_get_port_dev() {
    local dev=$1
    local pci_dev=`devlink port show | grep -w "netdev $dev" | cut -d":" -f1`
    echo $pci_dev
}

function devlink_dev_set_param() {
    local dev=$1
    local param_name=$2
    local value=$3
    local cmode=${4:-driverinit}

    log "devlink set param dev $dev name $param_name value $value"
    devlink dev param set $dev name $param_name value $value cmode $cmode || err "Failed to set $dev param $param_name=$value"
}

function devlink_dev_get_param() {
    local dev=$1
    local param_name=$2

    devlink dev param show $dev name $param_name &>/dev/null || err_stderr "Failed to get $dev param $param_name"
    devlink dev param show $dev name $param_name | grep "cmode .* value " | awk '{print $4}'
}

function devlink_dev_reload() {
    local dev=${1:-$NIC}
    local pci_dev

    if [ "$dev" == "$NIC" ]; then
        pci_dev="pci/$PCI"
    elif [ "$dev" == "$NIC2" ]; then
        pci_dev="pci/$PCI2"
    else
	pci_dev=`devlink_get_port_dev $dev`
	if [ -z "$pci_dev" ]; then
	    pci_dev=$dev
	fi
    fi

    log "devlink reload dev $dev pci $pci_dev"
    devlink dev reload $pci_dev || err "Failed devlink reload"
}

function devlink_dev_set_eq() {
    local io_eq_size=$1
    local event_eq_size=$2
    local devs=${@:3}
    local dev

    [ -z "$devs" ] && err "devlink_dev_set_eq: empty dev list" && return

    for dev in $devs; do
        devlink_dev_set_param $dev io_eq_size $io_eq_size
        devlink_dev_set_param $dev event_eq_size $event_eq_size
        devlink_dev_reload $dev
    done
}

function devlink_get_sfs() {
    devlink dev show | grep -w sf
}
