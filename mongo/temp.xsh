#!/usr/bin/env xonsh

import json
import logging
import argparse

from utils.general import *
from utils.constants import *
from resources.slowness.slow import slow_inject

class MongoDB:
    def __init__(self, **kwargs):
        opt = kwargs.get("opt")
        self.ondisk = opt.ondisk
        self.server_configs, self.servermap, _ = config_parser(opt.server_configs)
        self.workload = opt.workload
        self.threads = opt.threads
        self.runtime = opt.runtime
        self.diagnose = opt.diagnose
        self.exp = kwargs.get("exp")
        self.swap = True if self.exp == "6" else False
        self.exp_type = "noslow" if self.exp == "noslow" else opt.exp_type
        self.trial = kwargs.get("trial")
        results_path = os.path.join(opt.output_path, "mongodb_{}_{}_{}_{}_results".format(self.exp_type,"swapon" if self.swap else "swapoff", self.ondisk, self.threads))
        mkdir -p @(results_path)
        self.results_txt = os.path.join(results_path,"{}_{}.txt".format(self.exp,self.trial))
        self.diag_output = "???"
        self.init_script_path = os.path.join(os.path.dirname(os.path.realpath(__file__)), "init_script.js")
        self.fetchprimary_path = os.path.join(os.path.dirname(os.path.realpath(__file__)), "fetchprimary.js")
        self.cleanup_script_path = os.path.join(os.path.dirname(os.path.realpath(__file__)), "cleanup_script.js")
        self.primaryip = None
        self.primarypid = None
        self.secondaryip = None
        self.secondarypid = None
        self.slowdownip = None
        self.slowdownpid = None


    #cleans up the data storage directories
    def mongo_data_cleanup(self):
        data_cleanup(self.server_configs, "/data1/mongodb-data")


    # init is called to initialise the db servers
    def init(self):
        init_disk(self.server_configs, "/data1","/dev/sdc1", self.exp, "xfs", 1000, 1400000)
        for server_config in self.server_configs:
            ssh -i ~/.ssh/id_rsa @(server_config["privateip"]) "sudo sh -c 'sudo mkdir /data1/mongodb-data ; sudo chmod o+w /data1/mongodb-data'"
        set_swap_config(self.server_configs, self.swap, "/data1/swapfile", 1024, 20485760)
    


    # start_db starts the database instances on each of the server
    def start_db(self):
        for server_config in self.server_configs:
            ssh  -i ~/.ssh/id_rsa @(server_config["privateip"]) @("sh -c 'numactl --interleave=all taskset -ac 0 {} --replSet rs0 --bind_ip localhost,{} --fork --logpath /tmp/mongod.log --dbpath /data1/mongodb-data'".format(MONGOD, server_config["name"]))
        sleep 30


    # db_init initialises the database
    def db_init(self):
        @(MONGO) --host @(self.server_configs[0]["name"]) < @(self.init_script_path)
        
        # Wait for startup
        sleep 60

        response = $(@(MONGO) --host @(self.server_configs[0]["name"]) < @(self.fetchprimary_path) | tail -n +5 | head -n -1)
        mongo_servers = json.loads(response)

        for mongo_server in mongo_servers:
            if mongo_server["stateStr"] == "PRIMARY":
                self.primaryip = self.servermap[mongo_server["name"]]["privateip"]
            elif mongo_server["stateStr"] == "SECONDARY":
                self.secondaryip = self.servermap[mongo_server["name"]]["privateip"]

        primarypid=$(ssh -i ~/.ssh/id_rsa @(self.primaryip) "sh -c 'pgrep mongo'")
        secondarypid=$(ssh -i ~/.ssh/id_rsa @(self.secondaryip) "sh -c 'pgrep mongo'")

        if self.exp_type == "follower":
            self.slowdownpid=int(secondarypid)
            self.slowdownip=self.secondaryip  
        elif self.exp_type == "leader":
            self.slowdownpid=int(primarypid)
            self.slowdownip=self.primaryip

        # Disable chaining allowed
        @(MONGO) --host @(self.primaryip) --eval "cfg = rs.config(); cfg.settings.chainingAllowed = false; rs.reconfig(cfg);"
        primary_server = self.servermap[self.primaryip]["name"]
        for server_config in self.server_configs:
            if server_config["name"] == primary_server:
                continue
            @(MONGO) --host @(server_config["name"]) --eval @("db.adminCommand( {{ replSetSyncFrom: '{}:27017'}})".format(primary_server))

        # Set WriteConcern==majority    in order to make it consistent between all DBs
        @(MONGO) --host @(self.primaryip) --eval "cfg = rs.config(); cfg.settings.getLastErrorDefaults = { j:true, w:'majority', wtimeout:10000 }; rs.reconfig(cfg);"


    # ycsb_load is used to run the ycsb load and wait until it completes.
    def ycsb_load(self):
        @(YCSB) load mongodb -s -P @(self.workload) -threads @(self.threads) -p mongodb.url=@("mongodb://{}:27017/ycsb?w=majority&readConcernLevel=majority".format(self.primaryip))


    # ycsb run exectues the given workload and waits for it to complete
    def ycsb_run(self):
        @(YCSB) run mongodb -s -P @(self.workload) -threads @(self.threads)  -p maxexecutiontime=@(self.runtime) -p mongodb.url=@("mongodb://{}:27017/ycsb?w=majority&readConcernLevel=majority".format(self.primaryip)) > @(self.results_txt)


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
        @(MONGO) --host @(self.primaryip) < @(self.cleanup_script_path)
        @(MONGO) --host @(self.primaryip) --eval "db.getCollectionNames().forEach(function(n){db[n].remove()});"
        sleep 5


    def server_cleanup(self):
        cleanup(self.server_configs, "/data1","/dev/sdc1", "mongod", self.swap, "/data1/swapfile")


    def init_script(self):
        rm -rf @(self.init_script_path)
        members = ""
        for idx, server_config in enumerate(self.server_configs):
            members = members + "{{ _id: {}, host: \"{}:27017\" }},".format(idx, server_config["name"])

        query = "rs.initiate( {{_id : \"rs0\", members: [{}]}})".format(members[:-1])
        with open(self.init_script_path,"w") as f:
            f.write(query)


    def run(self):
        self.init_script()
        start_servers(self.server_configs)
        sleep 30
        self.mongo_data_cleanup()
        self.server_cleanup()
        self.init()
        self.start_db()
        self.db_init()   
        self.ycsb_load()
        
        if self.exp_type != "noslow" and self.exp != "noslow":
            slow_inject(self.exp, HOSTID, self.slowdownip, self.slowdownpid)

        if self.diagnose:
            self.mdiag()

        sleep 30

        self.ycsb_run()


        if self.diagnose:
            self.copy_diag()

        self.mongo_cleanup()

        sleep 30

        self.server_cleanup()
        self.mongo_data_cleanup()
        stop_servers(self.server_configs)


    def cleanup(self):
        start_servers(self.server_configs)
        self.server_cleanup()
        self.mongo_data_cleanup()
        stop_servers(self.server_configs)

