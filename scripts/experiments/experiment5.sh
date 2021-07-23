#!/bin/bash

set -ex

ip=$1

ssh -i ~/.ssh/id_rsa modb@"$ip" "sudo sh -c 'sudo /sbin/tc qdisc add dev eth0 root netem delay 400ms'"
