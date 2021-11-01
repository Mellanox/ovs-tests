OVN_DIR=$(cd "$(dirname ${BASH_SOURCE[0]})" &>/dev/null && pwd)

. $OVN_DIR/../common.sh
. $OVN_DIR/common-ovn.sh
. $OVN_DIR/common-ovn-topology.sh

# OVN IPs
OVN_LOCAL_CENTRAL_IP="127.0.0.1"
OVN_CENTRAL_IP="192.168.100.100"
OVN_REMOTE_CONTROLLER_IP="192.168.100.101"

require_ovn
