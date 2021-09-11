#!/usr/bin/env xonsh

import json
import logging
import argparse

from result_gen import *
from utils.general import *
# from utils.constants import *
from resources.slowness.slow import slow_inject

class PolarDB:
    def __init__(self, **kwargs):
        opt = kwargs.get("opt")
        
	# self.ondisk = opt.ondisk    # TBD: PolarDB (PG) does not have an option for ondisk or inmem. But this feature can be implemented using Ramdisk
        self.server_configs, self.servermap = config_parser(opt.configs)
        # self.workload = opt.workload  # the scale factor of pgbench: workload * 1000
        self.pgbench_scalefactor = opt.pgbench_scalefactor
        self.threads = opt.threads    # thread here means the number of logical clients 
        self.runtime = opt.runtime
	# self.diagnose = opt.diagnose    # not quite sure how to acquire diagnositic information from PG or PolarDB 
        self.exp_type = "noslow" if self.exp == "noslow" else opt.exp_type
        self.trial = kwargs.get("trial")
	results_path = os.path.join(opt.output_path, "polardb_{}_{}_results".format(self.exp_type, self.threads) # removed some params
	mkdir -p @(results_path)
	self.results_text = os.path.join(results.path, "{}_{}.txt".format(self.exp, self.trial))
	# self.diag_output = "???"

	self.masterip = self.server_configs[0]["privateip"] 
        self.followerip = self.server_configs[1]["privateip"]
	self.learnerip = self.server_configs[2]["privateip"]
        self.slowdownip = None
    def polar_data_cleanup(self):

    def init(self):
        # disk is automatically mounted during setup_servers stage, we omit the procedure here.
	# currently nothing has to be done in this function
	pass

    # start_db uses pgxc_ctl on the master node to initiate the cluster
    def start_db(self):
        polar_cleanup()
        # ssh @(self.masterip) "pgxc_ctl -c ~/polardb/paxos_multi.conf clean all"
        ssh @(self.masterip) "pgxc_ctl -c ~/polardb/paxos_multi.conf init force all"
        ssh @(self.masterip) "psql -p 10001 -d postgres -c 'create database pgbench;'"

    def db_init(self):
        if self.exp_type == "leader":
	    self.slowdownip = self.masterip
	elif self.exp_type == "follower":
            self.slowdownip = self.followerip
        elif self.exp_type == "learner":
            self.slowdownip = self.learnerip
        else 
            # nothing to do 
            # input checking should be done at the instantination of the class object

    def pgbench_load(self):
        ssh @(self.masterip) "pgbench -i -s @(self.pgbench_scalefactor) -p 10001 -d pgbench"

    def pgbench_run(self):
        ssh @(self.masterip) "rm -rf ~/trial* ~/Trial"


        tmp_out = $(ssh @(self.masterip) "pgbench -M prepared -r -c @(self.threads) -j 1 -T @(self.runtime) -p 10001 -d pgbench -l --log-prefix=trial | tail -n22") 
        ssh @(self.masterip) "cat trial* > Trial"
        num_tran = int($(ssh @(self.masterip) "cat Trial* | wc").split()[0])
 
        # P99 calculation
        p99 = float($(ssh @(self.masterip) "sort ~/Trial* -k3rn|head -n @(int(num_tran/100))|tail -n 1").split()[2])

        p99_9 = float($(ssh @(self.masterip) "sort ~/Trial* -k3rn|head -n @(int(num_tran/1000))|tail -n 1").split()[2])
        p50 = float($(ssh @(self.masterip) "sort ~/Trial* -k3rn|head -n @(int(num_tran/2))|tail -n 1").split()[2])
        
        result_gen(results_text, tmp_out, p99_9, p99, p50)

        
    def mdiag(self):
        pass
    def copy_diag(self):
    def polar_cleanup(self):
        ssh @(self.masterip) "pgxc_ctl -c ~/polardb/paxos_multi.conf clean all"

    # clean up the slowness config8
    def server_cleanup(self):
        ssh @(self.masterip) "sudo sh -c 'sudo /sbin/tc qdisc del dev eth0 root; true'"
        ssh @(self.masterip) "sudo cgdelete cpu:db cpu:cpulow cpu:cpuhigh blkio:db memory:db; true"

    def init_script(self):
    def run(self):
        start_servers(self.server_configs)
        sleep 30
        self.server_cleanup()
        # self.init()
        self.start_db()
        self.db_init()
        self.pgbench_load()
        
        if self.exp_type != "noslow" and self.exp !="noslow":
            self.slowdownpids = $(ssh @(self.slowdownip) "pgrep postgres")
            slow_inject(self.exp, HOSTID, self.slowdownip, self.slowdownpids)
        
        self.pgbench_run()

        self.polar_cleanup()
        self.server_cleanup()
        stop_servers(self.server_configs)
    
    def cleanup(self):
        start_servers(self.server_configs)
        self.server_cleanup()
        self.polar_cleanup()
        stop_servers(self.server_configs)
