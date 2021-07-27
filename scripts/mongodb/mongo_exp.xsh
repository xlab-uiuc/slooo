#!/usr/bin/env xonsh

import json
import logging
import argparse

from utils.general import *
from utils.constants import *


class MongoDB:
    def __init__(self, **kwargs):
        opt = kwargs.get("opt")
        self.ondisk = opt.ondisk
        self.server_configs, self.servermap = config_parser(opt.server_configs)
        self.swap = opt.swap
        self.workload = opt.workload
        self.threads = opt.threads
        self.runtime = opt.runtime
        self.diagnose = opt.diagnose
        self.exp_type = "noslow" if opt.exp_type == "" else opt.exp_type
        self.exp = kwargs.get("exp")
        self.trial = kwargs.get("trial")
        results_path = os.path.join(opt.output_path, "mongodb_{}_{}_{}_{}_results".format(self.exp_type,self.swap, self.ondisk, self.threads))
        mkdir -p results_path
        self.result_txt = os.path.join(results_path,"{}_{}.txt".format(self.exp,self.trial))
        self.diag_output = "???"


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
                ssh  -i ~/.ssh/id_rsa @(server_config["privateip"]) @("sh -c 'numactl --interleave=all taskset -ac 0 {} --replSet rs0 --bind_ip localhost,{} --fork --logpath /tmp/mongod.log --dbpath /ramdisk/mongodb-data'".format(MONGO, server_config["name"]))
        else:
            for server_config in self.server_configs:
                ssh  -i ~/.ssh/id_rsa @(server_config["privateip"]) @("sh -c 'numactl --interleave=all taskset -ac 0 {} --replSet rs0 --bind_ip localhost,{} --fork --logpath /tmp/mongod.log --dbpath /data1/mongodb-data'".format(MONGO, server_config["name"]))
        sleep 30


    # db_init initialises the database
    def db_init(self):
        @(MONGO) --host @(server_configs[0]["name"]) < init_script.js
        
        # Wait for startup
        sleep 60

        response = $(@(MONGO) --host @(server_configs[0]["name"]) < fetchprimary.js | tail -n +5 | head -n -1)
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
        @(MONGO) --host @(self.primaryip) --eval "cfg = rs.config(); cfg.settings.chainingAllowed = false; rs.reconfig(cfg);"
        primary_server = self.servermap[self.primaryip]["name"]
        for server_config in self.server_configs:
            if server_config["name"] == primary_server:
                continue
            @(MONGO) --host @(server_config["name"]) --eval @("db.adminCommand( { replSetSyncFrom: '{}:27017'})".format(primary_server))

        # Set WriteConcern==majority    in order to make it consistent between all DBs
        @(MONGO) --host @(self.primaryip) --eval "cfg = rs.config(); cfg.settings.getLastErrorDefaults = { j:true, w:'majority', wtimeout:10000 }; rs.reconfig(cfg);"


    # ycsb_load is used to run the ycsb load and wait until it completes.
    def ycsb_load(self):
        @(YCSB) load mongodb -s -P @(self.workload)  -threads 32 -p mongodb.url=@("mongodb://{}:27017/ycsb?w=majority&readConcernLevel=majority".format(self.primaryip)) ; wait $!


    # ycsb run exectues the given workload and waits for it to complete
    def ycsb_run(self):
        @(YCSB) run mongodb -s -P @(workload) -threads @(self.threads)  -p maxexecutiontime=@(self.runtime) -p mongodb.url=@("mongodb://{}:27017/ycsb?w=majority&readConcernLevel=majority".format(self.primaryip)) > @(self.results_txt) ; wait $!


    def mdiag(self):
        for server_config in self.server_configs:
            ssh  -i ~/.ssh/id_rsa @(server_config["privateip"]) "sh -c 'cd ~ && ./mdiag.sh'"
        
        for server_config in self.server_configs:
            scp -r @(HOSTID)@@(server_config["privateip"]):/tmp/mdiag-"$s1name".json @(self.diag_output)

        for server_config in self.server_configs:        
            ssh  -i ~/.ssh/id_rsa @(server_config["privateip"]) @("sh -c 'rm -rf /tmp/mdiag-{}.json'".format(server_config["name"]))


    def copy_diag(self):
        for server_config in self.server_configs:
            scp -r @(HOSTID)@@(server_config["privateip"]):/data1/mongodb-data/diagnostic.data/ @(self.diag_output) ### change the output path should be per server


    # cleanup is called at the end of the given trial of an experiment
    def mongo_cleanup(self):
        @(MONGO) --host @(self.primaryip) < cleanup_script.js
        @(MONGO) --host @(self.primaryip) --eval "db.getCollectionNames().forEach(function(n){db[n].remove()});"
        sleep 5


    def node_cleanup(self):
        for server_config in self.server_configs:
            ssh -i ~/.ssh/id_rsa @(server_config["privateip"]) "sudo cgdelete cpu:db cpu:cpulow cpu:cpuhigh blkio:db memory:db ; true"
            ssh -i ~/.ssh/id_rsa @(server_config["privateip"]) "sudo /sbin/tc qdisc del dev eth0 HOSTID ; true"
            sleep 5


    def slowness_inject(self):
        ./@(os.path.join(SLOW_SCRIPTS_PATH, self.exp)).sh "$slowdownip" "$slowdownpid" @(HOSTID)
        sleep 30


    def init_script(self):        
        members = ""
        for idx, server_config in enumerate(self.server_configs):
            members = members + "{{ _id: {}, host: \"{}:27017\" }},".format(idx, server_config["name"])

        query = "rs.initiate( {{_id : \"rs0\", members: [{}]}})".format(members[:-1])
        with open("./init_script.js","w") as f:
            f.write(query)


    def run(self):
        self.init_script()
        start_servers(self.server_configs)
        self.node_cleanup()
        self.init()
        self.start_db()
        self.db_init()   
        self.ycsb_load()
        
        if self.exp_type != "noslow":
            self.slowness_inject()

        if self.diagnose:
            self.mdiag()

        self.ycsb_run()

        if self.diagnose:
            self.copy_diag()

        self.mongo_cleanup()
        self.node_cleanup()
        self.data_cleanup()
        stop_servers(self.server_configs)


    def cleanup(self):
        start_servers(self.server_configs)
        self.node_cleanup()
        self.data_cleanup()
        stop_servers(self.server_configs)



def parse_opt():
    parser = argparse.ArgumentParser()
    parser.add_argument("--iters", type=int, default=1, help="number of iterations")
    parser.add_argument("--workload", type=str, default="./../workloads/workloads", help="workload path")
    parser.add_argument("--server-configs", type=str, default="./server_configs.json", help="server config path")
    parser.add_argument("--runtime", type=int, default=300, help="runtime")
    parser.add_argument("--exps", type=str, default="noslow", help="experiments to be ran saperated by commas(,)")
    parser.add_argument("--exp-type", type=str, default="", help="leader/follower")
    parser.add_argument("--swap", action='store_true', help="Swapniess on")
    parser.add_argument("--ondisk", type=str, default="disk", help="in memory(mem) or on disk (disk)")
    parser.add_argument("--threads", type=int, default=250, help="no. of logical clients")
    parser.add_argument("--diagnose", action='store_true', help="collect diagnostic data")
    parser.add_argument("--output-path", type=str, default="./../../results/mongodb/", help="results output path")
    parser.add_argument("--cleanup", action='store_true', help="clean's up the servers")
    opt = parser.parse_args()
    return opt

def main(opt):
    if opt.cleanup:
        mgb = MongoDB(opt=opt)
        mgb.cleanup()
        return

    for iter in range(opt.iters):
        exps = [exp.strip() for exp in opt.exps.split(",")]
        for exp in exps:
            mgb = MongoDB(opt=opt,trial=trial,exp=exp)
            mgb.run()

if __name__ == "__main__":
    opt = parse_opt()
    main(opt)
