#!/bin/bash
#
# Bug SW #1223798: [ASAP MLNX OFED] Call trace from act_mirred module
#

NIC=${1:-ens5f0}

my_dir="$(dirname "$0")"
. $my_dir/common.sh

TMPFILE=/tmp/rules-$$
RUNFILE=/tmp/test-$$
RULE_COUNT=${RULE_COUNT:-100}
GROUP_COUNT=${GROUP_COUNT:-50}
ROUND_COUNT=${ROUND_COUNT:-50}
ROUND_LOOP=${ROUND_LOOP:-200}

rm -f $TMPFILE
rm -f $RUNFILE

title "Test"
title "- generate rules"

# c is count of rules added
c=1
for p1 in {1..30}; do
    p2=25
    echo "tc filter add dev $NIC parent ffff: protocol ip pref $c handle $c flower skip_hw dst_mac e4:1d:2d:5d:25:40 dst_ip 1.1.1.4/$p1 action mirred egress redirect dev $NIC 2>/dev/null"
    let c++
    echo "tc filter add dev $NIC parent ffff: protocol ip pref $c handle $c flower skip_hw dst_mac e4:1d:2d:5d:25:41 src_ip 1.1.1.3/$p1 action mirred egress redirect dev $NIC 2>/dev/null"
    let c++
    echo "tc filter add dev $NIC parent ffff: protocol ip pref $c handle $c flower skip_hw dst_mac e4:1d:2d:5d:25:42 dst_ip 1.1.1.4/$p1 action mirred egress redirect dev $NIC 2>/dev/null"
    let c++
    echo "tc filter add dev $NIC parent ffff: protocol ip pref $c handle $c flower skip_hw dst_mac e4:1d:2d:5d:25:43 src_ip 1.1.1.3/$p1 action mirred egress redirect dev $NIC 2>/dev/null"
    let c++
    echo "tc filter add dev $NIC parent ffff: protocol ip pref $c handle $c flower skip_hw dst_mac e4:1d:2d:5d:25:44 src_mac e4:1d:2d:5d:25:60 dst_ip 1.1.1.4/$p1 action mirred egress redirect dev $NIC 2>/dev/null"
    let c++
    echo "tc filter add dev $NIC parent ffff: protocol ip pref $c handle $c flower skip_hw dst_mac e4:1d:2d:5d:25:45 src_mac e4:1d:2d:5d:25:61 src_ip 1.1.1.3/$p1 action mirred egress redirect dev $NIC 2>/dev/null"
    let c++
    echo "tc filter add dev $NIC parent ffff: protocol ip pref $c handle $c flower skip_hw dst_mac e4:1d:2d:5d:25:46 src_ip 1.1.1.2/$p1 dst_ip 1.1.1.2/$p2 action mirred egress redirect dev $NIC 2>/dev/null"
    let c++
    echo "tc filter add dev $NIC parent ffff: protocol ip pref $c handle $c flower skip_hw dst_mac e4:1d:2d:5d:25:47 src_mac e4:1d:2d:5d:25:62 src_ip 1.1.1.2/$p1 dst_ip 1.1.1.2/$p2 action mirred egress redirect dev $NIC 2>/dev/null"
    let c++
    echo "tc filter add dev $NIC parent ffff: protocol ip pref $c handle $c flower skip_hw dst_mac e4:1d:2d:5d:25:48 src_ip 1.1.1.2/$p1 dst_ip 1.1.1.2/$p2 action mirred egress redirect dev $NIC 2>/dev/null"
    let c++
    echo "tc filter add dev $NIC parent ffff: protocol ip pref $c handle $c flower skip_hw dst_mac e4:1d:2d:5d:25:49 src_mac e4:1d:2d:5d:25:62 src_ip 1.1.1.2/$p1 dst_ip 1.1.1.2/$p2 action mirred egress redirect dev $NIC 2>/dev/null"
    let c++

    if [ $((c/2)) -gt $GROUP_COUNT ]; then
        break
    fi
done >> $TMPFILE

let c--
for j in `seq $c`; do
    echo "tc filter del dev $NIC parent ffff: pref $j handle $j flower 2>/dev/null"
done >> $TMPFILE

title "- generate script"

for r in `seq $ROUND_COUNT`; do
    echo "function round_$r() {"
    for p in `seq $RULE_COUNT`; do
        echo -n "  "; shuf -n 1 $TMPFILE
        echo "  logf \$1 $p \$?"
    done
    echo "}"
done >> $RUNFILE

cat >>$RUNFILE <<EOF
function logf() {
  #if [ "\$3" != 0 ]; then
  #  echo "tc cmd failed at \$2 (round \$1)"
  #fi
  now=\`date +"%s"\`
  sec=\`echo \$now - \$_start_ts + 1 | bc\`
  journalctl --since="\$sec seconds ago" | grep WARN && echo "failed at \$2 (round \$1)" && exit 1
}

sleep 1
_start_ts=\`date +"%s"\`

tc qdisc del dev $NIC ingress 2>/dev/null
set -e
tc qdisc add dev $NIC ingress
modprobe -rv cls_flower act_mirred
modprobe -av cls_flower act_mirred
set +e

for i in \`seq $ROUND_LOOP\`; do
    r=\$((\$i%$ROUND_COUNT+1))
    eval "round_\$r \$r" &
#    echo "round \$i/$ROUND_LOOP complete"
done
wait
tc qdisc del dev $NIC ingress
echo "done"
EOF

title "- execute"
sh $RUNFILE || fail "script $RUNFILE failed."

rm -f $TMPFILE
rm -f $RUNFILE
test_done
