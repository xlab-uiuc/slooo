#!/usr/bin/env xonsh

import pdb
import sys
import json
import logging
from rethinkdb import r

from utils.rsm import RSM
from utils.general import *
from utils.constants import *
from resources.slowness.slow import slow_inject

class RethinkDB(RSM):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.pyserver = self.server_configs[len(self.server_configs)-1]["ip"]
        self.pyserver_offset = int(self.server_configs[len(self.server_configs)-1]["port_offset"])
        results_path = os.path.join(self.output_path, "rethink_{}_{}_{}_{}_results".format(self.exp_type,"swapon" if self.swap else "swapoff", self.ondisk, self.threads))
        mkdir -p @(results_path)
        self.results_txt = os.path.join(results_path,"{}_{}.txt".format(self.exp,self.trial))

    # def rethink_data_cleanup(self):
    #     data_cleanup(self.server_configs, "/data")


    def server_setup(self):
        super().server_setup()
        for cfg in self.server_configs:
            ssh -i ~/.ssh/id_rsa @(cfg["ip"]) @(f"sudo sh -c 'sudo mkdir {cfg['dbpath']}; sudo chmod o+w {cfg['dbpath']}'")


    # start_db starts the database instances on each of the server
    def start_db(self):
        cluster_port = None
        join_ip = None
        for idx, cfg in enumerate(self.server_configs):
            if idx==0:
                ssh -i ~/.ssh/id_rsa @(cfg["ip"]) @(f"sh -c 'taskset -ac {cfg['cpu']} rethinkdb --directory {cfg['dbpath']} --port-offset {cfg['port_offset']} --bind all --server-name {cfg['name']} --daemon'")
                join_ip = cfg["ip"]
                cluster_port = 29015 + int(cfg["port_offset"])
            else:
                ssh -i ~/.ssh/id_rsa @(cfg["ip"]) @(f"sh -c 'taskset -ac {cfg['cpu']} rethinkdb --directory {cfg['dbpath']} --port-offset {cfg['port_offset']} --join {join_ip}:{cluster_port} --bind all --server-name {cfg['name']} --daemon'")


    # db_init initialises the database
    def db_init(self):
        print("connecting to server ", self.pyserver)
        r.connect(self.pyserver, 28015 + self.pyserver_offset).repl()
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

        if self.exp_type == "follower":
            self.slowdownpid=int(secondarypid)
            self.slowdownip=self.secondaryip
        elif self.exp_type == "leader":
            self.slowdownpid=int(primarypid)
            self.slowdownip=self.primaryip

        for cfg in self.server_configs:
            if cfg["name"] == primaryreplica:
                self.primaryport = 28015 + int(cfg["port_offset"])


    # ycsb_load is used to run the ycsb load and wait until it completes.
    def ycsb_load(self):
        @(self.client_configs["ycsb"]) load rethinkdb -s -P @(self.workload) -p rethinkdb.host=@(self.primaryip) -p rethinkdb.port=@(self.primaryport) -threads @(self.threads)

    # ycsb run exectues the given workload and waits for it to complete
    def ycsb_run(self):
        @(self.client_configs["ycsb"]) run rethinkdb -s -P @(self.workload) -p maxexecutiontime=@(self.runtime) -p rethinkdb.host=@(self.primaryip) -p rethinkdb.port=@(self.primaryport) -threads @(self.threads) > @(self.results_txt)

    def db_cleanup(self):
        print("connecting to server ", self.pyserver)
        r.connect(self.pyserver, 28015 + self.pyserver_offset).repl()
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


    # test_run is the main driver function
    def run(self):
        start_servers(self.server_configs)

        #self.rethink_data_cleanup()	
        self.server_cleanup()
        self.server_setup()
        self.start_db()
        sleep 20
        self.db_init()
        self.ycsb_load()

        if self.exp_type != "noslow" and self.exp != "noslow":
            slow_inject(self.exp, HOSTID, self.slowdownip, self.slowdownpid)

        self.ycsb_run()

        self.db_cleanup()
        self.server_cleanup()
        # self.rethink_data_cleanup()
        stop_servers(self.server_configs)
