#!/bin/sh

match=${1:-test-*.sh}

for i in `ls -1 $match`; do
    tag=`echo $i | cut -d- -f 2`
    issues=`head $i | grep -E -o "Bug SW #[0-9]*:" | grep -o "[0-9]*"`
    A=""
    bugs=""
    for j in $issues ; do
        bugs="$bugs
            <bug> $j </bug>"
    done
    if [ -n "$bugs" ]; then
        A="
        <ignore>$bugs
        </ignore>"
    fi
    cat <<EOF
    <case>$A
        <tags> $tag </tags>
        <name> $i </name>
        <cmd>
            <params>
                <test> $i </test>
            </params>
        </cmd>
    </case>
EOF
done
