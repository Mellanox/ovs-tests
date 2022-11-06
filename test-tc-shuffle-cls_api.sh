#!/bin/bash
#
# reload module act_gact before adding rules to get into the request_module flow in gact
# which will return EAGAIN and expose bug in cls_api module.
#
# BugSW #1294281: [ASAP MLNX OFED] kernel crash adding drop rules when act_gact is not loaded
#


my_dir="$(dirname "$0")"
. $my_dir/common.sh

TMPFILE=/tmp/rules-$$
RUNFILE=/tmp/test-$$
RULE_COUNT=${RULE_COUNT:-60}
GROUP_COUNT=${GROUP_COUNT:-30}
ROUND_COUNT=${ROUND_COUNT:-50}

function get_mlx5_core_ver() {
    local A
    A=`modinfo -F version mlx5_core` && A=${A::3}
    echo $A
}

if [ `uname -r` = "3.10.0-327.el7.x86_64" ]; then
    ver=`get_mlx5_core_ver`
    if [ $ver == "4.2" ] || [ $ver == "4.5" ]; then
        fail "Bug SW #1294281: [ASAP MLNX OFED] kernel crash adding drop rules when act_gact is not loaded"
    fi
fi

rm -f $TMPFILE
rm -f $RUNFILE

enable_switchdev

title "Test"
title "- generate rules"

# c is count of rules added
c=1
for p1 in {1..30}; do
    p2=25
    echo "tc filter add dev $NIC parent ffff: protocol ip pref $c handle $c flower skip_hw action drop 2>/dev/null"
    let c++

    if [ $((c/2)) -gt $GROUP_COUNT ]; then
        break
    fi
done >> $TMPFILE

let c--
for j in `seq $c`; do
    echo "tc filter del dev $NIC parent ffff: pref $j 2>/dev/null"
done >> $TMPFILE

title "- generate script $ROUND_COUNT rounds $RULE_COUNT rules"

for r in `seq $ROUND_COUNT`; do
    echo "function round_$r() {"
    echo "  round=$r"
    echo
    shuf -n $RULE_COUNT $TMPFILE
    echo
    echo "}"
done >> $RUNFILE

cat >>$RUNFILE <<EOF
function tc() {
  command tc \$@
  rc=\$?
#  logf
}

function logf() {
#  if [ "\$rc" != 0 ]; then
#    echo "tc cmd failed \$rc at round \$round"
#    exit 1
#  fi
  now=\`date +"%s"\`
  sec=\`echo \$now - \$_start_ts + 1 | bc\`
  journalctl --since="\$sec seconds ago" | grep WARN && echo "failed at round \$round" && exit 1
  return 0
}

sleep 1
_start_ts=\`date +"%s"\`

tc qdisc del dev $NIC ingress 2>/dev/null
set -e
tc qdisc add dev $NIC ingress
modprobe -rv cls_flower act_gact
set +e

for i in \`seq $ROUND_COUNT\`; do
    eval "round_\$i \$i" &
    #echo "round \$i/$ROUND_COUNT complete"
done

wait
tc qdisc del dev $NIC ingress

now=\`date +"%s"\`
sec=\`echo \$now - \$_start_ts + 1 | bc\`
journalctl --since="\$sec seconds ago" | grep WARN && echo "failed at round \$round" && exit 1
echo "done"
EOF

title "- execute $ROUND_COUNT loops"
bash $RUNFILE || fail "script $RUNFILE failed."

rm -f $TMPFILE
rm -f $RUNFILE
test_done
