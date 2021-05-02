#!/bin/bash
#
# #1333837: In inline-mode transport UDP fragments from VF are dropped
#

NIC=${1:-ens5f0}
VF=${2:-ens5f2}
REP=${3:-ens5f0_0}
my_dir="$(dirname "$0")"
. $my_dir/common.sh

enable_switchdev
unbind_vfs
set_eswitch_inline_mode_transport
bind_vfs

ifconfig $REP up
ifconfig $VF up

FAKE_MAC="a2:b4:c0:f0:fc:8b"

function send_pkt() {
    local D=$1
    local pkt="Ether(dst=\"$FAKE_MAC\")/$D"

    title "sending $pkt"
    python -c "from scapy.all import sendp, Ether, IP, Dot1Q; sendp($pkt, iface=\"$VF\")"
}

function run_test() {
    local D=$1
    # verify we have packet with fragment offset > 0
    timeout 4 tcpdump -nnvei $REP -c 1 ether "dst $FAKE_MAC and ip[6:2] & 0x1fff > 0" &
    sleep 1
    tdpid=$!

    send_pkt $D
    wait $tdpid
    rc=$?
    if [[ $rc -eq 0 ]]; then
        success
    else
        err
    fi
}


ICMP=1
TCP=6
UDP=17

PROTOS="ICMP TCP UDP"
SIZES="1 7 8 9"

echo "Sending icmp packet for python scapy warmup"
# warmup for slow debug VMs
M1="IP(frag=5,dst=\"2.2.2.2\",proto=1)/(\"X\"*1)"
send_pkt $M1

for P in $PROTOS; do
    title "Test procotol $P"
    P=${!P}

    for S in $SIZES; do
        M1="IP(frag=5,dst=\"2.2.2.2\",proto=$P)/(\"X\"*$S)"
        run_test $M1

        M2="Dot1Q(vlan=2)/$M1"
        run_test $M2
    done
done

test_done
