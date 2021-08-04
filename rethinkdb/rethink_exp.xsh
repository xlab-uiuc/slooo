#!/usr/bin/env xonsh

import json
import logging
import argparse
from rethinkdb import r
import pdb
import sys

from utils.general import *
from utils.constants import *

class RethinkDB:
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
        results_path = os.path.join(opt.output_path, "rethink_{}_{}_{}_{}_results".format(self.exp_type,"swapon" if self.swap else "swapoff", self.ondisk, self.threads))
        mkdir -p @(results_path)
        self.results_txt = os.path.join(results_path,"{}_{}.txt".format(self.exp,self.trial))

    def rethink_data_cleanup(self):
        if self.ondisk == "mem":
            data_cleanup(self.server_configs, "/ramdisk")
        else:
            data_cleanup(self.server_configs, "/data")

    def init(self):
        if self.ondisk == "disk":
            init_disk(self.server_configs, "/data","/dev/sdc1", 1000, 1800000)
            set_swap_config(self.swap, "/data/swapfile", 1024, 20485760)
        elif self.ondisk == "mem":
            init_memory(self.server_configs, "/ramdisk")
            set_swap_config(self.swap)


    # start_db starts the database instances on each of the server
    def start_db(self):
        counter = 0
        clusterPort = 29015
        joinIP = None
        if self.ondisk == "mem":
            datadir = "ramdisk"
        elif self.ondisk == "disk":
            datadir = "data"
        for server_config in self.server_configs:
            if counter == 0:
                ssh -i ~/.ssh/id_rsa @(server_config["privateip"]) @(f"sh -c 'taskset -ac 0 rethinkdb --directory /{datadir}/rethinkdb_data1 --bind all --server-name $key --daemon'")
                joinIP=server_config["privateip"]
            else
                ssh -i ~/.ssh/id_rsa @(server_config["privateip"]) @(f"sh -c 'taskset -ac 0 rethinkdb --directory /{datadir}/rethinkdb_data1 --join {joinIP}:{clusterPort} --bind all --server-name $key --daemon'")
            counter = counter + 1
        sleep 20

    # db_init initialises the database
    def db_init(self):
        serverIP=""
        r.connect(serverIP, 28015).repl()
        # Connection established
        try:
            r.db('ycsb').table_drop('usertable').run()
        except Exception as e:
            print("Could not delete table")
        try:
            r.db_drop('ycsb').run()
        except Exception as e:
            print("Could not delete db")

        try:
            r.db_create('ycsb').run()
            r.db('ycsb').table_create('usertable', replicas=3,primary_key='__pk__').run()
        except Exception as e:
            print("Could not create table")

        # Print the primary name
        b = list(r.db('rethinkdb').table('table_status').run())
        primaryreplica = b[0]['shards'][0]['primary_replicas'][0]

        replicas = b[0]['shards'][0]['replicas']
        secondaryreplica = ""
        for rep in replicas:
            if rep['server'] != primaryreplica:
                secondaryreplica = rep['server']
                break


        res = list(r.db('rethinkdb').table('server_status').run())
        namePidIpRes = [(n['name'],n['process']['pid'],n['network']['canonical_addresses'][0]['host']) for n in res]
        

        self.primarypid, self.secondarypid, self.primaryip, self.secondaryip = "", "", "", ""
        for p in namePidIpRes:
            if p[0] == primaryreplica:
                self.primarypid = p[1]
                self.primaryip = p[2]
            if p[0] == secondaryreplica:
                self.secondarypid = p[1]
                self.secondaryip = p[2]

    # ycsb_load is used to run the ycsb load and wait until it completes.
    def ycsb_load(self):
        @(YCSB) load rethinkdb -s -P @(self.workload) -p rethinkdb.host=@(self.primaryip) -p rethinkdb.port=28015 -threads 20

    # ycsb run exectues the given workload and waits for it to complete
    def ycsb_run(self):
        @(YCSB) run rethinkdb -s -P @(self.workload) -p maxexecutiontime=@(self.runtime) -p rethinkdb.host=@(self.primaryip) -p rethinkdb.port=28015 -threads @(self.threads) > @(self.results_txt)

    def rethink_cleanup(self):
        serverIP = ""
        print("connecting to server ", serverIP)
        r.connect(serverIP, 28015).repl()
        # Connection established
        try:
            r.db('ycsb').table_drop('usertable').run()
        except Exception as e:
            print("Could not delete table")
        try:
            r.db_drop('ycsb').run()
        except Exception as e:
            print("Could not delete db")
        print("DB and table deleted")

    
    def server_cleanup(self):
        for server_config in server_configs:
            ssh -i ~/.ssh/id_rsa @(server_config["privateip"]) "sudo sh -c 'pkill rethinkdb'"
        if self.ondisk == "disk":
            cleanup(self.server_configs, "/data","/dev/sdc1", self.swap, "/data/swapfile")
        else:
            cleanup(self.server_configs, "/ramdisk","tmpfs", self.swap)


    # test_run is the main driver function
    def run(self):
        start_servers(self.server_configs)
        sleep 30

        self.rethink_data_cleanup()	
        self.server_cleanup()
        self.init()
        self.start_db()
        self.db_init()
        self.ycsb_load()

        if self.exp_type != "noslow" and self.exp != "noslow":
            slowness_inject(self.exp, self.slowdownip, self.slowdownpid)

        self.ycsb_run()

        self.rethink_cleanup()
        self.server_cleanup()
        self.rethink_data_cleanup()
        stop_servers(self.server_configs)


    def cleanup(self):
        start_servers(self.server_configs)
        self.server_cleanup()
        self.rethink_data_cleanup()
        stop_servers(self.server_configs)