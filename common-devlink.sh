function devlink_get_pci_dev() {
    local pci_dev=`devlink_get_port_dev $1`
    pci_dev=${pci_dev%/*}
    echo $pci_dev
}

function devlink_get_port_dev() {
    local dev=$1
    local pci_dev=`devlink port show | grep "netdev $dev" | cut -d" " -f1`
    echo $pci_dev
}

function devlink_dev_set_param() {
    local dev=$1
    local param_name=$2
    local value=$3
    local cmode=${4:-driverinit}
    local pci_dev=`devlink_get_pci_dev $dev`

    devlink dev param set $pci_dev name $param_name value $value cmode $cmode || err "Failed to set $dev param $param_name=$value"

    if [ "$cmode" == "driverinit" ]; then
        devlink dev reload $pci_dev
    fi
}

function devlink_dev_set_eq() {
    local io_eq_size=$1
    local event_eq_size=$2
    local devs=${@:3}
    local dev

    for dev in $devs; do
        devlink_dev_set_param $dev io_eq_size $io_eq_size
        devlink_dev_set_param $dev event_eq_size $event_eq_size
    done
}

function devlink_get_sfs() {
    devlink port show | grep mlx5_core.sf. | grep -E -o "netdev [a-z0-9]+" | awk {'print $2'}
}
