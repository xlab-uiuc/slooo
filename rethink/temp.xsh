#!/usr/bin/env xonsh

import pdb
import sys
import json
import logging
import argparse
from rethinkdb import r

from utils.rsm import RSM
from utils.general import *
from utils.constants import *
from resources.slowness.slow import slow_inject

class RethinkDB(RSM):
    def __init__(self, **kwargs):
        super.__init__(**kwargs)
        self.pyserver = self.server_configs[len(self.server_configs)-1]["privateip"]
        results_path = os.path.join(opt.output_path, "rethink_{}_{}_{}_{}_results".format(self.exp_type,"swapon" if self.swap else "swapoff", self.ondisk, self.threads))
        mkdir -p @(results_path)
        self.results_txt = os.path.join(results_path,"{}_{}.txt".format(self.exp,self.trial))

    # def rethink_data_cleanup(self):
    #     data_cleanup(self.server_configs, "/data")


    def server_setup(self):
        init_disk(self.server_configs, "/data","/dev/sdc", self.exp, "xfs", 1000, 1800000)
        set_swap_config(self.server_configs, self.swap, "/data/swapfile", 1024, 20485760)


    # start_db starts the database instances on each of the server
    def start_db(self):
        clusterPort = 29015
        joinIP = None
        datadir = "data"
        for idx, server_config in enumerate(self.server_configs):
            if idx==0:
                ssh -i ~/.ssh/id_rsa @(server_config["privateip"]) @("sh -c 'taskset -ac 0 rethinkdb --directory /{}/rethinkdb_data1 --bind all --server-name {} --daemon'".format(datadir, server_config["name"]))
                joinIP=server_config["privateip"]
            else:
                ssh -i ~/.ssh/id_rsa @(server_config["privateip"]) @("sh -c 'taskset -ac 0 rethinkdb --directory /{}/rethinkdb_data1 --join {}:{} --bind all --server-name {} --daemon'".format(datadir, joinIP, clusterPort, server_config["name"]))
        sleep 20

    # db_init initialises the database
    def db_init(self):
        serverIP=self.pyserver
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

        try:
            r.db_create('ycsb').run()
            r.db('ycsb').table_create('usertable', replicas=len(self.server_configs),primary_key='__pk__').run()
        except Exception as e:
            print("Could not create table")

        # Print the primary name
        b = list(r.db('rethinkdb').table('table_status').run())
        primaryreplica = b[0]['shards'][0]['primary_replicas'][0]
        print("primaryreplica=", primaryreplica, sep='')

        replicas = b[0]['shards'][0]['replicas']
        secondaryreplica = ""
        for rep in replicas:
            if rep['server'] != primaryreplica:
                secondaryreplica = rep['server']
                break
        print("secondaryreplica=", secondaryreplica, sep='')


        res = list(r.db('rethinkdb').table('server_status').run())
        namePidIpRes = [(n['name'],n['process']['pid'],n['network']['canonical_addresses'][0]['host']) for n in res]
        

        for p in namePidIpRes:
            if p[0] == primaryreplica:
                self.primarypid = p[1]
                self.primaryip = p[2]
            if p[0] == secondaryreplica:
                self.secondarypid = p[1]
                self.secondaryip = p[2]

        print("primarypid=", self.primarypid, sep='')
        print("secondarypid=", self.secondarypid, sep='')
        print("primaryip=", self.primaryip, sep='')
        print("secondaryip=", self.secondaryip, sep='')

    # ycsb_load is used to run the ycsb load and wait until it completes.
    def ycsb_load(self):
        @(YCSB) load rethinkdb -s -P @(self.workload) -p rethinkdb.host=@(self.primaryip) -p rethinkdb.port=28015 -threads @(self.threads)

    # ycsb run exectues the given workload and waits for it to complete
    def ycsb_run(self):
        @(YCSB) run rethinkdb -s -P @(self.workload) -p maxexecutiontime=@(self.runtime) -p rethinkdb.host=@(self.primaryip) -p rethinkdb.port=28015 -threads @(self.threads) > @(self.results_txt)

    def rethink_cleanup(self):
        serverIP = self.pyserver
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
        for server_config in self.server_configs:
            ssh -i ~/.ssh/id_rsa @(server_config["privateip"]) "sudo sh -c 'pkill rethinkdb'"
        
        cleanup(self.server_configs, "/data","/dev/sdc", "rethinkdb", self.swap, "/data/swapfile")


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
            slow_inject(self.exp, HOSTID, self.slowdownip, self.slowdownpid)
        
        sleep 30

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
