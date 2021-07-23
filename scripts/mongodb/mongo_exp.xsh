#!/usr/bin/env xonsh

import json
import logging
import argparse

from utils.general import *
from utils.constants import *

# server_config = {}
# name = "lol"
# cmd = f"sh -c 'numactl --interleave=all taskset -ac 0 /home/modb/mongodb/bin/mongod --replSet rs0 --bind_ip localhost,{name} --fork --logpath /tmp/mongod.log --dbpath /ramdisk/mongodb-data'"
# print(cmd)

class MongoDB:
    def __init__(self, **kwargs):


    #cleans up the data storage directories
    def data_cleanup(self):
        if self.ondisk == "mem":
            for server_config in self.server_configs:
                ssh -i ~/.ssh/id_rsa @(server_config["privateip"]) "sh -c 'sudo rm -rf /ramdisk/mongodb-data'"
        else:
            for server_config in self.server_configs:
                ssh -i ~/.ssh/id_rsa @(server_config["privateip"]) "sh -c 'sudo rm -rf /data1/mongodb-data'"

    # init is called to initialise the db servers
    def init(self):
        for server_config in self.server_configs:
            ssh -i ~/.ssh/id_rsa @(server_config["privateip"]) "sudo sh -c 'sudo umount /dev/sdc1 ; sudo mkdir -p /data1 ; sudo mkfs.xfs /dev/sdc1 -f ; sudo mount -t xfs /dev/sdc1 /data1 ; sudo mount -t xfs /dev/sdc1 /data1 -o remount,noatime ; sudo chmod o+w /data1 ; mkdir /data1/mongodb-data ; sudo chmod o+w /data1/mongodb-data'"

        for server_config in self.server_configs:
            ssh -i ~/.ssh/id_rsa @(server_config["privateip"]) "sudo sh -c 'nohup taskset -ac 1 dd if=/dev/zero of=/data1/tmp.txt bs=1000 count=1400000 conv=notrunc'"

        if self.swap:
            for server_config in self.server_configs:
                ssh -i ~/.ssh/id_rsa @(server_config["privateip"]) "sudo sh -c 'sudo dd if=/dev/zero of=/data1/swapfile bs=1024 count=20485760 ; sudo chmod 600 /data1/swapfile ; sudo mkswap /data1/swapfile'"  # 10GB
                ssh -i ~/.ssh/id_rsa @(server_config["privateip"]) "sudo sh -c 'sudo sysctl vm.swappiness=60 ; sudo swapoff -a && swapon -a ; sudo swapon /data1/swapfile'"
        else:
            for server_config in self.server_configs:
                ssh -i ~/.ssh/id_rsa @(server_config["privateip"]) "sudo sh -c 'sudo sysctl vm.swappiness=0 ; sudo swapoff -a && swapon -a'"

        if self.ondisk == "mem":
            for server_config in self.server_configs:
                ssh -i ~/.ssh/id_rsa @(server_config["privateip"]) "sudo sh -c 'sudo mkdir -p /ramdisk ; sudo mount -t tmpfs -o rw,size=8G tmpfs /ramdisk/ ; sudo chmod o+w /ramdisk/ ; mkdir /ramdisk/mongodb-data ; sudo chmod o+w /ramdisk/mongodb-data'"


    # start_db starts the database instances on each of the server
    def start_db(self):
        if self.ondisk == "mem":
            for server_config in self.server_configs:
                ssh  -i ~/.ssh/id_rsa @(server_config["privateip"]) @("sh -c 'numactl --interleave=all taskset -ac 0 {} --replSet rs0 --bind_ip localhost,{} --fork --logpath /tmp/mongod.log --dbpath /ramdisk/mongodb-data'".format(MONGO_PATH, server_config["name"]))
        else:
            for server_config in self.server_configs:
                ssh  -i ~/.ssh/id_rsa @(server_config["privateip"]) @("sh -c 'numactl --interleave=all taskset -ac 0 {} --replSet rs0 --bind_ip localhost,{} --fork --logpath /tmp/mongod.log --dbpath /data1/mongodb-data'".format(MONGO_PATH, server_config["name"]))
        sleep 30

    # db_init initialises the database
    def db_init(self):
        @(MONGO_PATH) --host @(server_configs[0]["name"]) < init_script.js
        
        # Wait for startup
        sleep 60

        response = $(@(MONGO_PATH) --host @(server_configs[0]["name"]) < fetchprimary.js | tail -n +5 | head -n -1)
        mongo_servers = json.loads(response)

        for mongo_server in mongo_servers:
            if mongo_server["stateStr"] == "PRIMARY":
                self.primaryip = self.servermap[mongo_server["name"]]
            elif mongo_server["stateStr"] == "SECONDARY":
                self.secondaryip = self.servermap[mongo_server["name"]]

        primarypid=$(ssh -i ~/.ssh/id_rsa "$primaryip" "sh -c 'pgrep mongo'")
        secondarypid=$(ssh -i ~/.ssh/id_rsa "$secondaryip" "sh -c 'pgrep mongo'")

        if exptype == "follower":
            slowdownpid=secondarypid
            slowdownip=self.secondaryip  
        elif exptype == "leader":
            slowdownpid=primarypid
            slowdownip=self.primaryip

        # Disable chaining allowed
        @(MONGO_PATH) --host @(self.primaryip) --eval "cfg = rs.config(); cfg.settings.chainingAllowed = false; rs.reconfig(cfg);"
        primary_server = self.servermap[self.primaryip]["name"]
        for server_config in self.server_configs:
            if server_config["name"] == primary_server:
                continue
            @(MONGO_PATH) --host @(server_config["name"]) --eval @("db.adminCommand( { replSetSyncFrom: '{}:27017'})".format(primary_server))

        # Set WriteConcern==majority    in order to make it consistent between all DBs
        @(MONGO_PATH) --host @(self.primaryip) --eval "cfg = rs.config(); cfg.settings.getLastErrorDefaults = { j:true, w:'majority', wtimeout:10000 }; rs.reconfig(cfg);"


    # ycsb_load is used to run the ycsb load and wait until it completes.
    def ycsb_load(self):
        @(YCSB_PATH) load mongodb -s -P @(self.workload)  -threads 32 -p mongodb.url=@("mongodb://{}:27017/ycsb?w=majority&readConcernLevel=majority".format(self.primaryip)) ; wait $!


    # ycsb run exectues the given workload and waits for it to complete
    def ycsb_run(self):
        @(YCSB_PATH) run mongodb -s -P @(workload) -threads @(self.threads)  -p maxexecutiontime=@(self.runtime) -p mongodb.url=@("mongodb://{}:27017/ycsb?w=majority&readConcernLevel=majority".format(self.primaryip)) > @(self.output_path) ; wait $!

    def mdiag(self):
        for server_config in self.server_configs:
            ssh  -i ~/.ssh/id_rsa @(server_config["privateip"]) "sh -c 'cd ~ && ./mdiag.sh'"

        ##mkdir -p /home/modb/slooo_mongo/old_stuff/scripts/mongodb/"$dirname"/exp"$expno"_trial_"$trial"_diag_s1/
        
        for server_config in self.server_configs:
            scp -r @(ROOT)@@(server_config["privateip"]):/tmp/mdiag-"$s1name".json @(self.diag_output)

        for server_config in self.server_configs:        
            ssh  -i ~/.ssh/id_rsa @(server_config["privateip"]) @("sh -c 'rm -rf /tmp/mdiag-{}.json'".format(server_config["name"]))


    def copy_diag(self):
        for server_config in self.server_configs:
            scp -r @(ROOT)@@(server_config["privateip"]):/data1/mongodb-data/diagnostic.data/ @(self.diag_output) ### change the output path should be per server


    # cleanup is called at the end of the given trial of an experiment
    def mongo_cleanup(self):
        @(MONGO_PATH) --host @(self.primaryip) < cleanup_script.js
        @(MONGO_PATH) --host @(self.primaryip) --eval "db.getCollectionNames().forEach(function(n){db[n].remove()});"
        sleep 5

    def node_cleanup(self):
        for server_config in server_configs:
            ssh -i ~/.ssh/id_rsa @(server_config["privateip"]) "sudo cgdelete cpu:db cpu:cpulow cpu:cpuhigh blkio:db memory:db ; true"
            ssh -i ~/.ssh/id_rsa @(server_config["privateip"]) "sudo /sbin/tc qdisc del dev eth0 root ; true"
            sleep 5





def parse_opt():
    parser = argparse.ArgumentParser()
    parser.add_argument("--iters", type=int, default=1, help="number of iterations")
    parser.add_argument("--workload", type=str, default="???", help="workload path")
    parser.add_argument("--server-configs", type=str, default="???", help="server config path")
    parser.add_argument("--runtime", type=int, default=300, help="runtime")
    parser.add_argument("--exps", type=str, default="noslow", help="experiments to be ran saperated by commas(,)")
    parser.add_argument("--exp-type", type=str, default="follower", help="leader/follower")
    parser.add_argument("--swap", type=bool, default=False, help="Swapniess on/off")
    parser.add_argument("--ondisk", type=str, default="disk", help="in memory(mem) or on disk (disk)")
    parser.add_argument("--threads", type=int, default=100, help="no. of logical clients")
    parser.add_argument("--diagnose", type=bool, default=False, help="collect diagnostic data")
    parser.add_argument("--output-path", type=str, default="????", help="results output path")
    opt = parser.parse_args()
    return opt

def main(opt):
    for iter in opt.iters:


if __name__ == "__main__":
    opt = parse_opt()
    main(opt)
