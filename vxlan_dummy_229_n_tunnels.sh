#!/bin/bash

ifconfig enp6s0f0 up
ip addr add 70.70.70.229/24 dev enp6s0f0
ip link add name vxlan42 type vxlan id 42 dev enp6s0f0  remote 70.70.70.2 dstport 4789
ifconfig vxlan42 1.1.42.229/24 up

ip addr add 71.71.71.229/24 dev enp6s0f0
ip link add name vxlan44 type vxlan id 44 dev enp6s0f0  remote 71.71.71.2 dstport 4790
ifconfig vxlan44 1.1.44.229/24 up

ip addr add 81.81.81.229/24 dev enp6s0f0
ip link add name vxlan46 type vxlan id 46 dev enp6s0f0  remote 81.81.81.2 dstport 4791
ifconfig vxlan46 1.1.46.229/24 up
