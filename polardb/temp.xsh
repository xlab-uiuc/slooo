#!/usr/bin/env xonsh

import sys,os,json
import logging
import argparse

from utils.rsm import RSM
from utils.general import *
from utils.constants import *
from resources.slowness.slow import slow_inject

class PolarDB(RSM):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.pgbench_scalefactor = int(self.workload)
        
        self.masterip = self.server_configs[0]["privateip"] 
        self.followerip = self.server_configs[1]["privateip"]
        self.learnerip = self.server_configs[2]["privateip"]
        self.slowdownip = None
        
        self.pidslist = []
        self.ppidlist = []

    def server_setup(self):
        super().server_setup()
        for server_config in self.server_configs:
            ssh -i ~/.ssh/id_rsa @(server_config["privateip"]) @(f"sudo sh -c 'sudo mkdir {server_config["dbpath"]};\
                                                     sudo chmod o+w {server_config["dbpath"]}'")
    
    # start_db starts the databse instances on each of the server by using pgxc_ctl on the master node to initiate the cluster
    def start_db(self):
        ssh @(self.masterip) "pgxc_ctl -c ~/polardb/paxos_multi.conf init force all"
        ssh @(self.masterip) "psql -p 10001 -d postgres -c 'create database pgbench;'"
    # 
    def get_pidslist(self):
        # NOTE: POLARDB SPECIFIC
        for server_config in self.server_configs:
            ppid_str = $(ssh @(server_config["privateip"]) f"ps -ef | grep {server_config['process']} | grep {server_config['role']}")
            ppid_str = ppid_str.split('\n')[0].split()[1]
            self.ppidlist.append(ppid_str)
            pids_str = ppid_str + '\n' + $(ssh @(server_config["privateip"]) f"pgrep -P {ppid_str}")
            self.pidslist.append(pids_str)

    def set_affinity(self):
        for i, server_config in enumerate(self.server_configs):
            for pid in self.pidslist[i].split():
                ssh @(server_config["privateip"]) @(f"taskset -acp {server_config["cpu"]} {pid}")

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
        self.result_extract(tmp_out)

        
            
    def polar_cleanup(self):
        ssh @(self.masterip) "pgxc_ctl -c ~/polardb/paxos_multi.conf clean all"


    def run(self):
        start_servers(self.server_configs)
        super().server_cleanup()
        self.start_db()
        self.db_init()
        self.pgbench_load()
        # TODO adapt to local mode please
        self.get_pidslist()
        self.set_affinity()
        
        if self.exp_type != "noslow" and self.exp !="noslow":
             
            self.slowdownpids = $(ssh @(self.slowdownip) "pgrep postgres")
            slow_inject(self.exp, HOSTID, self.slowdownip, self.slowdownpids) # CPU
        
        self.pgbench_run()
        
        self.polar_cleanup()
        super().server_cleanup()
        stop_servers(self.server_configs)
    
    def result_extract(self, tmp_out):
        ssh @(self.masterip) "cat trial* > Trial"
        num_tran = int($(ssh @(self.masterip) "cat Trial* | wc").split()[0])
        p99 = float($(ssh @(self.masterip) @("sort ~/Trial* -k3rn|head -n {} |tail -n 1".format(int(num_tran/100)))).split()[2])
        p99_9 = float($(ssh @(self.masterip) @("sort ~/Trial* -k3rn|head -n {} |tail -n 1".format(int(num_tran/1000)))).split()[2])
        throughput = tmp_out.split('\n')[8][6:-37].strip()
        
        self.result_gen("polardb",throughtput, p99_9, p99)
