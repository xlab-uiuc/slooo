#!/usr/bin/env xonsh

import json
import logging
import argparse

from utils.rsm import RSM
from utils.general import *
from utils.constants import *
from resources.slowness.slow import slow_inject

class MongoDB(RSM):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        results_path = os.path.join(self.output_path, "mongodb_{}_{}_{}_{}_results".format(self.exp_type,"swapon" if self.swap else "swapoff", self.ondisk, self.threads))
        mkdir -p @(results_path)
        self.results_txt = os.path.join(results_path,"{}_{}.txt".format(self.exp,self.trial))
        self.init_script_path = os.path.join(os.path.dirname(os.path.realpath(__file__)), "init_script.js")
        self.fetchprimary_path = os.path.join(os.path.dirname(os.path.realpath(__file__)), "fetchprimary.js")
        self.cleanup_script_path = os.path.join(os.path.dirname(os.path.realpath(__file__)), "cleanup_script.js")


    # #cleans up the data storage directories
    # def mongo_data_cleanup(self):
    #     data_cleanup(self.server_configs)


    # init is called to initialise the db servers
    def server_setup(self):
        super().server_setup()
        for server_config in self.server_configs:
            ip = server_config["privateip"]
            dbpath = server_config["dbpath"]
            ssh -i ~/.ssh/id_rsa @(ip) @(f"sudo sh -c 'sudo mkdir {dbpath};\
                                           sudo chmod o+w {dbpath}'")    

    # start_db starts the database instances on each of the server
    def start_db(self):
        for server_config in self.server_configs:
            ip = server_config["privateip"]
            mongod = server_config["mongod"]
            server_name = server_config["name"]
            dbpath = server_config["dbpath"]
            logpath = server_config["logpath"]
            port = server_config["port"]
            cpu_no = server_config["cpu"]
            ssh  -i ~/.ssh/id_rsa @(ip) @(f"sh -c 'numactl --interleave=all taskset -ac {cpu_no} {mongod} --replSet rs0 --bind_ip localhost,{server_name} --port {port} --fork --logpath {logpath} --dbpath {dbpath}'")


    # db_init initialises the database
    def db_init(self):
        client_mongo = self.client_configs["mongo"] 
        @(client_mongo) --host @(self.server_configs[0]["host"]) < @(self.init_script_path)
        
        # Wait for startup
        sleep 60

        response = $(@(client_mongo) --host @(self.server_configs[0]["host"]) < @(self.fetchprimary_path) | tail -n +5 | head -n -1)
        mongo_servers = json.loads(response)

        for mongo_server in mongo_servers:
            if mongo_server["stateStr"] == "PRIMARY":
                primary_server = mongo_server["name"].split(":")[0]
            elif mongo_server["stateStr"] == "SECONDARY":
                secondary_server = mongo_server["name"].split(":")[0]

        for server_config in self.server_configs:
            if primary_server == server_config["name"]:
                self.primaryip = server_config["privateip"]
                self.primaryhost = server_config["host"]
                primary_server_config = server_config
            elif secondary_server == server_config["name"]:
                self.secondaryip = server_config["privateip"]
                secondary_server_config = server_config

        #####PID LOGIC STILL TO BE ADDED
        pids=$(ssh -i ~/.ssh/id_rsa @(self.primaryip) "sh -c 'pgrep mongo'")
        pids = pids.split()
        for pid in pids:
            ac = $(ssh -i ~/.ssh/id_rsa @(self.primaryip) @(f"sh -c 'taskset -pc {pid}'"))
            if primary_server_config["cpu"] ==  int(ac.split(": ")[1]):
                primarypid = pid

        pids=$(ssh -i ~/.ssh/id_rsa @(self.secondaryip) "sh -c 'pgrep mongo'")
        pids = pids.split()
        for pid in pids:
            ac = $(ssh -i ~/.ssh/id_rsa @(self.secondaryip) @(f"sh -c 'taskset -pc {pid}'"))
            if secondary_server_config["cpu"] ==  int(ac.split(": ")[1]):
                secondarypid = pid

        if self.exp_type == "follower":
            self.slowdownpid=int(secondarypid)
            self.slowdownip=self.secondaryip  
        elif self.exp_type == "leader":
            self.slowdownpid=int(primarypid)
            self.slowdownip=self.primaryip

        # Disable chaining allowed
        @(client_mongo) --host @(self.primaryhost) --eval "cfg = rs.config();\
                                                         cfg.settings.chainingAllowed = false;\
                                                         rs.reconfig(cfg);"
        for server_config in self.server_configs:
            server_name = server_config["name"]
            server_host = server_config["host"]
            if server_name == primary_server:
                continue
            @(client_mongo) --host @(server_host) --eval @(f"db.adminCommand( {{ replSetSyncFrom: '{self.primaryhost}'}})")

        # Set WriteConcern==majority    in order to make it consistent between all DBs
        @(client_mongo) --host @(self.primaryhost) --eval "cfg = rs.config();\
                                                         cfg.settings.getLastErrorDefaults = { j:true, w:'majority', wtimeout:10000 };\
                                                         rs.reconfig(cfg);"


    # ycsb_load is used to run the ycsb load and wait until it completes.
    def ycsb_load(self):
        client_ycsb = self.client_configs["ycsb"]
        @(client_ycsb) load mongodb -s -P @(self.workload) -threads @(self.threads) -p mongodb.url=@(f"mongodb://{self.primaryhost}/ycsb?w=majority&readConcernLevel=majority")


    # ycsb run exectues the given workload and waits for it to complete
    def ycsb_run(self):
        client_ycsb = self.client_configs["ycsb"]
        @(client_ycsb) run mongodb -s -P @(self.workload) -threads @(self.threads)  -p maxexecutiontime=@(self.runtime) -p mongodb.url=@(f"mongodb://{self.primaryhost}/ycsb?w=majority&readConcernLevel=majority") > @(self.results_txt)


    # cleanup is called at the end of the given trial of an experiment
    def db_cleanup(self):
        client_mongo = self.client_configs["mongo"]
        @(client_mongo) --host @(self.primaryhost) < @(self.cleanup_script_path)
        @(client_mongo) --host @(self.primaryhost) --eval "db.getCollectionNames().forEach(function(n){db[n].remove()});"


    def server_cleanup(self):
        super().server_cleanup()


    def init_script(self):
        rm -rf @(self.init_script_path)
        members = ""
        for idx, server_config in enumerate(self.server_configs):
            server_host = server_config["host"]
            members = members + f"{{ _id: {idx}, host: \"{server_host}\" }},"

        query = "rs.initiate( {{_id : \"rs0\", members: [{}]}})".format(members[:-1])
        with open(self.init_script_path,"w") as f:
            f.write(query)


    ##ADD SLEEPS
    def run(self):
        self.init_script()

        start_servers(self.server_configs)

        # self.mongo_data_cleanup()
        self.server_cleanup()

        self.server_setup()
        self.start_db()
        self.db_init()

        self.ycsb_load()
        
        if self.exp_type != "noslow" and self.exp != "noslow":
            slow_inject(self.exp, HOSTID, self.slowdownip, self.slowdownpid)

        self.ycsb_run()

        self.db_cleanup()
        self.server_cleanup()
        # self.mongo_data_cleanup()

        stop_servers(self.server_configs)


    def cleanup(self):
        start_servers(self.server_configs)
        self.server_cleanup()
        stop_servers(self.server_configs)

