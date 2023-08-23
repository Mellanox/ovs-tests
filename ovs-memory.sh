#! /usr/bin/env bash

YELLOW="\e[33m"
CYAN="\e[36m"
NOCOLOR="\e[0m"

FULL=0

function usage() {
cat <<_END_OF_USAGE
Usage:
$0 \\
  -h | -help | --help    Show this help
  csv=<file>             Add output in Comma-Separated-Value format to a file
  section=<name>         Specialize the report title with a section name
  full                   Print all available measures
_END_OF_USAGE
    exit 0
}

for arg; do
case "$arg" in
-h|-help|--help) DO_USAGE=y ;;
csv=*) CSV="${arg#*=}" ;;
section=*) SECTION="${arg#*=}" ;;
full) FULL=1 ;;
*) echo "unknown option $arg"; FATAL=y ;;
esac
done

[ "$FATAL" ] && usage
[ "$DO_USAGE" ] && usage

# Convert bytes to power-of-two scale multipliers,
function convert_bytes_binary() {
    numfmt --to=iec-i --suffix=B --format="%.2f" "${1:-0}" | tr -d ' '
}

function ovs_detect_flavor() {
    if ovs-vsctl list o . 2> /dev/null | grep doca_initialized | grep -q 'true'; then
        printf "ovs-doca"
    elif ovs-vsctl list o . 2> /dev/null | grep dpdk_initialized | grep -q 'true'; then
        printf "ovs-dpdk"
    else
        printf "ovs-kernel"
    fi
}

# Functions returning OVS memory use in bytes.

function ovs_get_hugepage_heap_size() {
    ovs-appctl dpdk/get-malloc-stats 2> /dev/null |
        grep Heap_size |
        cut -d: -f 2 |
        tr -d , |
    (
        total=0
        while read -r size; do
            total=$((total+size))
        done
        printf "%d" $total
    )
}

function ovs_get_hugepage_mempool_size() {
    ovs-appctl dpdk/get-mempool-stats 2> /dev/null |
        grep '  size\|total_obj_size\|private_data_size' |
        cut -d= -f 2 |
        paste -d " " - - - | # Group every 3 lines
    (
        total=0
        while read -r n size priv; do
            total=$((total + n * (size + priv)))
        done
        printf "%d" $total
    )
}

function ovs_get_memory_rss() {
    ovs-appctl metrics/show 2> /dev/null |
        grep '^ovs_vswitchd_memory_rss' |
        cut -d' ' -f2 |
    (
        read -r v
        [ "$v" ] || v=0
        echo $v
    )
}

function ovs_get_memory_in_use() {
    ovs-appctl metrics/show 2> /dev/null |
        grep '^ovs_vswitchd_memory_in_use' |
        cut -d' ' -f2 |
    (
        read -r v
        [ "$v" ] || v=0
        echo $v
    )
}

function sanitize() {
    echo "$@" | tr -s ' ,:' '_' | tr -cd ' .\-_a-zA-Z0-9'
}

function print_field() (
    memtype="$1"
    field="${2}"
    bytes="${3}"
    section="${4}"
    if [ "$CSV" ]; then
        section="$(sanitize "$section")"
        printf "%s" "$OVS_FLAVOR" >> "$CSV"
        [ "$section" ] && printf "%c%s" "-" "${section}" >> "$CSV"
        printf ":%s_%s,%s\n" "$memtype" "$field" "$bytes" >> "$CSV"
    fi
    printf "${YELLOW}# ${CYAN}%-*s " 8 "$memtype"
    printf "%*s: ${NOCOLOR}" 10 "$field"
    printf "%*s\n" 9 "$(convert_bytes_binary "$bytes")"
)

OVS_FLAVOR="$(ovs_detect_flavor)"

# $1: Section name
function print_report() (
    section="${1}"
    printf "${YELLOW}####### ${OVS_FLAVOR^^} memory: %s${NOCOLOR}\n" "$section"
    if [ "$OVS_FLAVOR" != "ovs-kernel" ] || [ "$FULL" = 1 ]; then
        print_field hugepage   total "$(ovs_get_hugepage_heap_size)   " "${section}"
        if [ "$FULL" = 1 ]; then
            print_field hugepage mempool "$(ovs_get_hugepage_mempool_size)" "${section}"
        fi
    fi
    print_field  process    RSS "$(ovs_get_memory_rss)           " "${section}"
    if [ "$FULL" = 1 ]; then
        print_field  process  in-use "$(ovs_get_memory_in_use)        " "${section}"
    fi
)

print_report "$SECTION"
