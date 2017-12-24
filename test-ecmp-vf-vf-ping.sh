#!/bin/bash

my_dir="$(dirname "$0")"
. $my_dir/common.sh

MULTIPATH=1 test-vf-vf-ping.sh
