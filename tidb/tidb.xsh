#!/usr/bin/env xonsh

import json
import logging
import argparse
from rethinkdb import r
import pdb
import sys

from utils.general import *
from utils.constants import *

#!/bin/bash

set -ex

# Server specific configs
##########################
pd="10.0.0.5"
s1="10.0.0.6"
s2="10.0.0.7"
s3="10.0.0.9"

pdname="tidbtidbaa_pd"
s1name="tidbtidbaa_tikv1"
s2name="tidbtidbaa_tikv2"
s3name="tidbtidbaa_tikv3"
serverZone="us-central1-a"    # for gcp only
###########################

if [ "$#" -ne 9 ]; then
    echo "Wrong number of parameters"
    echo "1st arg - number of iterations"
    echo "2nd arg - workload path"
    echo "3rd arg - seconds to run ycsb run"
    echo "4th arg - experiment to run(1, 2, 3 only for hdd, 4 only for hdd, 5, 6 only for swapon+mem)"
    echo "5th arg - host type(gcp/aws)"
    echo "6th arg - type of experiment(follower/leaderlow/leaderhigh/noslow1/noslow2)"
    echo "7th arg - turn on swap (swapon/swapoff) [swapon only for exp6+mem] "
    echo "8th arg - in disk or in memory (hdd/mem)"
	echo "9th arg - threads for ycsb run(for saturation exp)"
    exit 1
fi

iterations=$1
workload=$2
ycsbruntime=$3
expno=$4
host=$5
exptype=$6
swapness=$7
ondisk=$8
ycsbthreads=$9

# test_start is executed at the beginning
function test_start {
  name=$1
  echo "Running $exptype experiment $expno $swapness $ondisk for $name"
  dirname="$name"_"$exptype"_"$swapness"_"$ondisk"_"$ycsbthreads"_results
  mkdir -p $dirname
}

# data_cleanup is called just after servers start
function data_cleanup {
  #ssh -i ~/.ssh/id_rsa tidb@"$pd" "./.tiup/bin/tiup cluster destroy mytidb -y"
  tiup cluster destroy mytidb -y
}

# start_servers is used to boot the servers up
function start_servers {  
  if [ "$host" == "gcp" ]; then
    gcloud compute instances start "$s1name" "$s2name" "$s3name" --zone="$serverZone"
  elif [ "$host" == "azure" ]; then
    az vm start --resource-group DepFast3 --subscription "Last Chance" --name "$pdname"
    az vm start --resource-group DepFast3 --subscription "Last Chance" --name "$s1name"
    az vm start --resource-group DepFast3 --subscription "Last Chance" --name "$s2name"
    az vm start --resource-group DepFast3 --subscription "Last Chance" --name "$s3name"
  else
    echo "Not implemented error"
    exit 1
  fi
  sleep 30
}

# init is called to initialise the db servers
function init {
#  ssh -i ~/.ssh/id_rsa "$s1" "sudo sh -c 'sudo parted -s -a optimal /dev/sdc mklabel gpt -- mkpart primary ext4 1 -1'"
#  ssh -i ~/.ssh/id_rsa "$s2" "sudo sh -c 'sudo parted -s -a optimal /dev/sdc mklabel gpt -- mkpart primary ext4 1 -1'"
#  ssh -i ~/.ssh/id_rsa "$s3" "sudo sh -c 'sudo parted -s -a optimal /dev/sdc mklabel gpt -- mkpart primary ext4 1 -1'"

  ssh -i ~/.ssh/id_rsa "$s1" "sudo sh -c 'sudo umount /dev/sdc1 ; sudo mkdir -p /data1 ; sudo mkfs.ext4 /dev/sdc1 -F ; sudo mount -t ext4 /dev/sdc1 /data1 -o defaults,nodelalloc,noatime ; sudo chmod o+w /data1/'"
  ssh -i ~/.ssh/id_rsa "$s2" "sudo sh -c 'sudo umount /dev/sdc1 ; sudo mkdir -p /data1 ; sudo mkfs.ext4 /dev/sdc1 -F ; sudo mount -t ext4 /dev/sdc1 /data1 -o defaults,nodelalloc,noatime ; sudo chmod o+w /data1/'"
  ssh -i ~/.ssh/id_rsa "$s3" "sudo sh -c 'sudo umount /dev/sdc1 ; sudo mkdir -p /data1 ; sudo mkfs.ext4 /dev/sdc1 -F ; sudo mount -t ext4 /dev/sdc1 /data1 -o defaults,nodelalloc,noatime ; sudo chmod o+w /data1/'"

  ssh -i ~/.ssh/id_rsa "$s1" "sudo sh -c 'nohup taskset -ac 1 dd if=/dev/zero of=/data1/tmp.txt bs=1000 count=1400000 conv=notrunc'"
  ssh -i ~/.ssh/id_rsa "$s2" "sudo sh -c 'nohup taskset -ac 1 dd if=/dev/zero of=/data1/tmp.txt bs=1000 count=1400000 conv=notrunc'"
  ssh -i ~/.ssh/id_rsa "$s3" "sudo sh -c 'nohup taskset -ac 1 dd if=/dev/zero of=/data1/tmp.txt bs=1000 count=1400000 conv=notrunc'"

  if [ "$swapness" == "swapoff" ] ; then
    ssh -i ~/.ssh/id_rsa "$s1" "sudo sh -c 'sudo sysctl vm.swappiness=0 ; sudo swapoff -a && swapon -a'"
    ssh -i ~/.ssh/id_rsa "$s2" "sudo sh -c 'sudo sysctl vm.swappiness=0 ; sudo swapoff -a && swapon -a'"
    ssh -i ~/.ssh/id_rsa "$s3" "sudo sh -c 'sudo sysctl vm.swappiness=0 ; sudo swapoff -a && swapon -a'"
  else
    ssh -i ~/.ssh/id_rsa "$s1" "sudo sh -c 'sudo dd if=/dev/zero of=/data1/swapfile bs=1024 count=25165824 ; sudo chmod 600 /data1/swapfile ; sudo mkswap /data1/swapfile'"  # 24GB
    ssh -i ~/.ssh/id_rsa "$s1" "sudo sh -c 'sudo sysctl vm.swappiness=60 ; sudo swapoff -a && swapon -a ; sudo swapon /data1/swapfile'"
    ssh -i ~/.ssh/id_rsa "$s2" "sudo sh -c 'sudo dd if=/dev/zero of=/data1/swapfile bs=1024 count=25165824 ; sudo chmod 600 /data1/swapfile ; sudo mkswap /data1/swapfile'"  # 24GB
    ssh -i ~/.ssh/id_rsa "$s2" "sudo sh -c 'sudo sysctl vm.swappiness=60 ; sudo swapoff -a && swapon -a ; sudo swapon /data1/swapfile'"
    ssh -i ~/.ssh/id_rsa "$s3" "sudo sh -c 'sudo dd if=/dev/zero of=/data1/swapfile bs=1024 count=25165824 ; sudo chmod 600 /data1/swapfile ; sudo mkswap /data1/swapfile'"  # 24GB
    ssh -i ~/.ssh/id_rsa "$s3" "sudo sh -c 'sudo sysctl vm.swappiness=60 ; sudo swapoff -a && swapon -a ; sudo swapon /data1/swapfile'"
  fi

  if [ "$ondisk" == "mem" ] ; then
    ssh -i ~/.ssh/id_rsa "$s1" "sudo sh -c 'sudo mkdir -p /ramdisk ; sudo mount -t tmpfs -o rw,size=8G tmpfs /ramdisk/ ; sudo chmod o+w /ramdisk/'"
    ssh -i ~/.ssh/id_rsa "$s2" "sudo sh -c 'sudo mkdir -p /ramdisk ; sudo mount -t tmpfs -o rw,size=8G tmpfs /ramdisk/ ; sudo chmod o+w /ramdisk/'"
    ssh -i ~/.ssh/id_rsa "$s3" "sudo sh -c 'sudo mkdir -p /ramdisk ; sudo mount -t tmpfs -o rw,size=8G tmpfs /ramdisk/ ; sudo chmod o+w /ramdisk/'"
  fi
}

# start_db starts the database instances on each of the server
function start_db {
  if [ "$ondisk" == "mem" ] ; then
    if [ "$exptype" == "follower" ] || [ "$exptype" == "noslow2" ] ; then
      # ssh -i ~/.ssh/id_rsa tidb@"$pd" "./.tiup/bin/tiup cluster deploy mytidb v4.0.0 ./tidb_restrict_mem.yaml --user tidb -y"
      tiup cluster deploy mytidb v4.0.0 ./tidb_restrict_mem.yaml --user tidb -y
    else
      #ssh -i ~/.ssh/id_rsa tidb@"$pd" "./.tiup/bin/tiup cluster deploy mytidb v4.0.0 ./tidb_mem.yaml --user tidb -y"
      tiup cluster deploy mytidb v4.0.0 ./tidb_mem.yaml --user tidb -y
    fi
    ssh -i ~/.ssh/id_rsa tidb@"$s1" "sudo sed -i 's#bin/tikv-server#taskset -ac 0 bin/tikv-server#g' /ramdisk/tidb-deploy/tikv-20160/scripts/run_tikv.sh "
    ssh -i ~/.ssh/id_rsa tidb@"$s2" "sudo sed -i 's#bin/tikv-server#taskset -ac 0 bin/tikv-server#g' /ramdisk/tidb-deploy/tikv-20160/scripts/run_tikv.sh "
    ssh -i ~/.ssh/id_rsa tidb@"$s3" "sudo sed -i 's#bin/tikv-server#taskset -ac 0 bin/tikv-server#g' /ramdisk/tidb-deploy/tikv-20160/scripts/run_tikv.sh "
  else
    if [ "$exptype" == "follower" ] || [ "$exptype" == "noslow2" ] ; then
      #ssh -i ~/.ssh/id_rsa tidb@"$pd" "./.tiup/bin/tiup cluster deploy mytidb v4.0.0 ./tidb_restrict_hdd.yaml --user tidb -y"
      tiup cluster deploy mytidb v4.0.0 ./tidb_restrict_hdd.yaml --user tidb -y
    else
      #ssh -i ~/.ssh/id_rsa tidb@"$pd" "./.tiup/bin/tiup cluster deploy mytidb v4.0.0 ./tidb_hdd.yaml --user tidb -y"
      tiup cluster deploy mytidb v4.0.0 ./tidb_hdd.yaml --user tidb -y
    fi
 
scp ~/tikv-server tidb@"$s1":/data1/tidb-deploy/tikv-20160/bin/
scp ~/tikv-server tidb@"$s2":/data1/tidb-deploy/tikv-20160/bin/ 
scp ~/tikv-server tidb@"$s3":/data1/tidb-deploy/tikv-20160/bin/

   
    ssh -i ~/.ssh/id_rsa tidb@"$s1" "sudo sed -i 's#bin/tikv-server#taskset -ac 0 bin/tikv-server#g' /data1/tidb-deploy/tikv-20160/scripts/run_tikv.sh "
    ssh -i ~/.ssh/id_rsa tidb@"$s2" "sudo sed -i 's#bin/tikv-server#taskset -ac 0 bin/tikv-server#g' /data1/tidb-deploy/tikv-20160/scripts/run_tikv.sh "
    ssh -i ~/.ssh/id_rsa tidb@"$s3" "sudo sed -i 's#bin/tikv-server#taskset -ac 0 bin/tikv-server#g' /data1/tidb-deploy/tikv-20160/scripts/run_tikv.sh "
  fi
  #ssh -i ~/.ssh/id_rsa tidb@"$pd" "./.tiup/bin/tiup cluster start mytidb"
  tiup cluster start mytidb
  sleep 30
}

# db_init initialises the database, get slowdownip and pid
function db_init {
  sleep 30
  if  [ "$exptype" == "follower" ] || [ "$exptype" == "noslow2" ] ; then
    tiup ctl pd config set label-property reject-leader dc 1 -u http://"$pd":2379     # leader is restricted to s3
    sleep 10
  fi
  if [ "$exptype" == "follower" ]; then
    followerip=$s1
    followerpid=$(ssh -i ~/.ssh/id_rsa tidb@"$followerip" "pgrep tikv-server")
    slowdownpid=$followerpid
    slowdownip=$followerip
    scp clear_dd_file.sh tidb@"$slowdownip":~/
    echo $exptype slowdownip slowdownpid
  elif [ "$exptype" == "leaderlow" ]; then
    leaderip=$(python3 getleader.py $pd min)
    leaderpid=$(ssh -i ~/.ssh/id_rsa tidb@"$leaderip" "pgrep tikv-server")
    slowdownpid=$leaderpid
    slowdownip=$leaderip
    scp clear_dd_file.sh tidb@"$slowdownip":~/
    echo $exptype slowdownip slowdownpid
  elif [ "$exptype" == "leaderhigh" ]; then
    leaderip=$(python3 getleader.py $pd max)
    leaderpid=$(ssh -i ~/.ssh/id_rsa tidb@"$leaderip" "pgrep tikv-server")
    slowdownpid=$leaderpid
    slowdownip=$leaderip
    scp clear_dd_file.sh tidb@"$slowdownip":~/
    echo $exptype slowdownip slowdownpid
  else
    # Nothing to do
    echo ""
  fi
}

# ycsb_load is used to run the ycsb load and wait until it completes.
function ycsb_load {
#  ./bin/ycsb load mongodb -s -P $workload -p mongodb.url=mongodb://$primaryip:27017/ycsb?w=majority&readConcernLevel=majority ; wait $!
  if [ "$ycsbthreads" == "1" ]; then
    /home/tidb/go-ycsb/bin/go-ycsb load tikv -P $workload -p tikv.pd="$pd":2379 --threads=16 ; wait $!
  else
    /home/tidb/go-ycsb/bin/go-ycsb load tikv -P $workload -p tikv.pd="$pd":2379 --threads=320 
  fi
}

# ycsb run exectues the given workload and waits for it to complete
function ycsb_run {
# 16 threads for saturation

#  ./bin/ycsb run mongodb -s -P $workload  -p maxexecutiontime=$ycsbruntime -p mongodb.url="mongodb://$primaryip:27017/ycsb?w=majority&readConcernLevel=majority" > "$dirname"/exp"$expno"_trial_"$i".txt ; wait $!
  /home/tidb/go-ycsb/bin/go-ycsb run tikv -P $workload -p tikv.pd="$pd":2379 --threads=$ycsbthreads > "$dirname"/exp"$expno"_trial_"$i".txt & ppid=$! ; sleep $ycsbruntime ; kill -INT $ppid
}

# cleanup is called at the end of the given trial of an experiment
function cleanup {
    ssh -i ~/.ssh/id_rsa tidb@"$s1" "sudo cgdelete cpu:db cpu:cpulow cpu:cpuhigh blkio:db memory:db ; true"
    ssh -i ~/.ssh/id_rsa tidb@"$s1" "sudo /sbin/tc qdisc del dev eth0 root ; true"
    ssh -i ~/.ssh/id_rsa tidb@"$s1" "sudo pkill dd ; rm /data1/tmp.txt -f"
    #ssh -i ~/.ssh/id_rsa tidb@"$s1" "sudo pkill deadloop"
    sleep 5
    ssh -i ~/.ssh/id_rsa tidb@"$s2" "sudo cgdelete cpu:db cpu:cpulow cpu:cpuhigh blkio:db memory:db ; true"
    ssh -i ~/.ssh/id_rsa tidb@"$s2" "sudo /sbin/tc qdisc del dev eth0 root ; true"
    ssh -i ~/.ssh/id_rsa tidb@"$s2" "sudo pkill dd ; rm /data1/tmp.txt -f"
    #ssh -i ~/.ssh/id_rsa tidb@"$s2" "sudo pkill deadloop"
    sleep 5
    ssh -i ~/.ssh/id_rsa tidb@"$s3" "sudo cgdelete cpu:db cpu:cpulow cpu:cpuhigh blkio:db memory:db ; true"
    ssh -i ~/.ssh/id_rsa tidb@"$s3" "sudo /sbin/tc qdisc del dev eth0 root ; true"
    ssh -i ~/.ssh/id_rsa tidb@"$s3" "sudo pkill dd ; rm /data1/tmp.txt -f"
    #ssh -i ~/.ssh/id_rsa tidb@"$s3" "sudo pkill deadloop"
    sleep 5
}

# stop_servers turns off the VM instances
function stop_servers {
  if [ "$host" == "gcp" ]; then
    gcloud compute instances stop "$s1name" "$s2name" "$s3name" --zone="$serverZone"
  elif [ "$host" == "azure" ]; then
    az vm deallocate --resource-group DepFast3 --subscription "Last Chance" --name "$s1name"
    az vm deallocate --resource-group DepFast3 --subscription "Last Chance" --name "$s2name"
    az vm deallocate --resource-group DepFast3 --subscription "Last Chance" --name "$s3name"
    az vm deallocate --resource-group DepFast3 --subscription "Last Chance" --name "$pdname"
  else
    echo "Not implemented error"
    exit 1
  fi
}

# run_experiment executes the given experiment
function run_experiment {
  ./experiment$expno.sh "$slowdownip" "$slowdownpid"
}

# test_run is the main driver function
function test_run {
  for (( i=1; i<=$iterations; i++ ))
  do
    echo "Running experiment $expno - Trial $i"
    # 1. start servers
    start_servers

    # 2. Cleanup first
    cleanup
#    data_cleanup

    # 3. Create data directories
    init

    #ssh -i ~/.ssh/id_rsa tidb@"$s1" "dd if=/dev/zero of=/data1/placeholder bs=1000 count=5000000"
    #ssh -i ~/.ssh/id_rsa tidb@"$s2" "dd if=/dev/zero of=/data1/placeholder bs=1000 count=5000000"
    #ssh -i ~/.ssh/id_rsa tidb@"$s3" "dd if=/dev/zero of=/data1/placeholder bs=1000 count=5000000"
    # 55000000

    # 4. SSH to all the machines and start db
    start_db

    # 5. ycsb load
    ycsb_load

    # 6. Init
    db_init

    #ycsb_load

    # 7. Run experiment if this is not a no slow
    if [ "$exptype" != "noslow1" ] && [ "$exptype" != "noslow2" ] ; then
      run_experiment
    fi

    sleep 30
    # 8. ycsb run
    ycsb_run

    # 9. cleanup
    cleanup

    sleep 120

mkdir tidblogs
mkdir tidblogs/ld tidblogs/sf tidblogs/ff
tiup ctl pd region -u http://10.0.0.5:2379 >> tidblogs/region
tiup ctl pd store -u http://10.0.0.5:2379 >> tidblogs/store
scp 10.0.0.9:/data1/tidb-deploy/tikv-20160/log/tikv.log* ./tidblogs/ld/
scp 10.0.0.6:/data1/tidb-deploy/tikv-20160/log/tikv.log* ./tidblogs/sf/
scp 10.0.0.7:/data1/tidb-deploy/tikv-20160/log/tikv.log* ./tidblogs/ff/


    data_cleanup
    
    # 10. Power off all the VMs
    stop_servers
  done
}

test_start tidb
test_run

# Make sure either shutdown is executed after you run this script or uncomment the last line
# sudo shutdown -h now
