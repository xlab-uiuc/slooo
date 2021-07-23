#!/bin/bash

 set -ex

 ip=$1

# Trigger file cleanup script first
#
# #ssh -i ~/.ssh/id_rsa "$ip" "sudo sh -c 'rm /data1/placeholder'"
#
 ssh -i ~/.ssh/id_rsa "$ip" "sh -c 'nohup taskset -ac 2 ./clear_dd_file.sh > /dev/null 2>&1 &'"
#
# ssh -i ~/.ssh/id_rsa "$ip" "sudo sh -c 'nohup taskset -ac 1 dd if=/dev/zero of=/data1/tmp.txt bs=1000 count=60000000 > /dev/null 2>&1 &'"
#


