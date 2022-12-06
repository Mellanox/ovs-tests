OVN_BASIC_DIR=$(cd "$(dirname ${BASH_SOURCE[0]})" && pwd)
. $OVN_BASIC_DIR/../common-ovn-test.sh
. $OVN_BASIC_DIR/common-ovn-basic.sh


function WA_dpdk_initial_ping_and_flush() {
    if [[ "$DPDK" == 1 ]]; then
        # WA RM #3287703 require initial traffic + flush to start working.
        echo "Init traffic"
        ip netns exec $CLIENT_NS ping -w 1 $SERVER_IPV4 &> /dev/null
        ovs_flush_rules
    fi
}
