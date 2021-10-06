#!/usr/bin/env xonsh

import json
import logging
import argparse

from utils.rsm import RSM
from utils.general import *
from utils.constants import *
from resources.slowness.slow import slow_inject
from polardb.result_gen import *

class PolarDB(RSM):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        #TODO workload used as pgbench's scale factor
        self.pgbench_scalefactor = int(self.workload)
        
        #TODO revisit here for result / figure generation
        self.results_path = os.path.join(self.output_path, "polardb_{}_{}_{}_{}_results".format(self.exp_type, "swapon" if self.swap else "swapoff", self.ondisk, self.threads))
        mkdir -p @(self.results_path)
        self.results_txt = os.path.join(self.results_path, f"{self.exp}_{self.trial}.txt")

        
        self.masterip = self.server_configs[0]["privateip"] 
        self.followerip = self.server_configs[1]["privateip"]
        self.learnerip = self.server_configs[2]["privateip"]
        self.slowdownip = None
        
        #TODO Revisit here (since it is included in new server)_configs.json)
        self.pidslist = []
        self.ppidlist = []
    #  # cleans up the data  storage directories
    # def polar_data_cleanup():
    #     data_cleanup(self.server_configs)

    # init is called to initialize the db servers
    def server_setup(self):
        # TODO revisit here
        super().server_setup()
        for server_config in self.server_configs:
            ip = server_config["privateip"]
            dbpath = server_config["dbpath"]
            ssh -i ~/.ssh/id_rsa @(ip) @(f"sudo sh -c 'sudo mkdir {dbpath};\
                                                     sudo chmod o+w {dbpath}'")
    
    # start_db starts the databse instances on each of the server by using pgxc_ctl on the master node to initiate the cluster
    def start_db(self):
        ssh @(self.masterip) "pgxc_ctl -c ~/polardb/paxos_multi.conf init force all"
        ssh @(self.masterip) "psql -p 10001 -d postgres -c 'create database pgbench;'"
    # 
    def get_pidslist():
        # NOTE: POLARDB SPECIFIC
	# TODO: The following information can also be grepped from server_config["process"]
        namelist = ["master", "slave", "follower"] # TODO TEST here. The order should matter.
        for i, name in enumerate(namelist):
	    ppid_str = $(ssh @(server_configs[i]["privateip"]) "pgrep master")
            self.ppidlist.append(ppid_str)
	    pids_str = $(ssh @(server_configs[i]["privateip"]) f"pgrep -P {self.ppidlist[i]}")
            self.pidslist.append(pids_str)

    def set_affinity(self):
        # TODO: MODIFY THIS
        for i, server_config in enumerate(self.server_configs):
            cpu = server_config["cpu"]
            for pid in self.pidslist[i].split():
                ssh @(server_config["privateip"]) @(f"taskset -aq {cpu} {pid}")

    def db_init(self):
        if self.exp_type == "leader":
            self.slowdownip = self.masterip
        elif self.exp_type == "follower":
            self.slowdownip = self.followerip
        elif self.exp_type == "learner":
            self.slowdownip = self.learnerip
        else: 
            pass
            # nothing to do 
            # input checking should be done at the instantination of the class object


    def pgbench_load(self):
        ssh @(self.masterip) @(f"pgbench -i -s {self.pgbench_scalefactor} -p 10001 -d pgbench")

    def pgbench_run(self):
        ssh @(self.masterip) "rm -rf ~/trial* ~/Trial"


        tmp_out = $(ssh @(self.masterip) @(f"pgbench -M prepared -r -c {self.threads} -j 1 -T {self.runtime} -p 10001 -d pgbench -l --log-prefix=trial | tail -n22")) 
        ssh @(self.masterip) "cat trial* > Trial"
        num_tran = int($(ssh @(self.masterip) "cat Trial* | wc").split()[0])
 
        # P99 calculation
        p99 = float($(ssh @(self.masterip) @("sort ~/Trial* -k3rn|head -n {} |tail -n 1".format(int(num_tran/100)))).split()[2])

        p99_9 = float($(ssh @(self.masterip) @("sort ~/Trial* -k3rn|head -n {} |tail -n 1".format(int(num_tran/1000)))).split()[2])
        p50 = float($(ssh @(self.masterip) @("sort ~/Trial* -k3rn|head -n {} |tail -n 1".format(int(num_tran/2)))).split()[2])
        
        result_gen(self.results_text, tmp_out, self.exp_type, self.exp, p99_9, p99, p50) #TODO use varshith's plot function

        
            
    def polar_cleanup(self):
        ssh @(self.masterip) "pgxc_ctl -c ~/polardb/paxos_multi.conf clean all"


    def run(self):
        start_servers(self.server_configs)
        super.server_cleanup()
        self.start_db()
        self.db_init()
        self.pgbench_load()
        # TODO adapt to local mode please
        self.set_affinity()
        
        if self.exp_type != "noslow" and self.exp !="noslow":
             
            self.slowdownpids = $(ssh @(self.slowdownip) "pgrep postgres")
            slow_inject(self.exp, HOSTID, self.slowdownip, self.slowdownpids) # CPU
        
        self.pgbench_run()
        
        self.polar_cleanup()
        super.server_cleanup()
        stop_servers(self.server_configs)
    
