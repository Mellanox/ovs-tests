#!/bin/bash

my_dir="$(dirname "$0")"

MULTIPATH=1
. $my_dir/test-vf-vf-different-esw-ping.sh
