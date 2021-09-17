#!/usr/bin/env xonsh

import json
import logging
import argparse

from polardb.result_gen import *
from utils.general import *
# from utils.constants import *
from resources.slowness.slow import slow_inject

class PolarDB:
    def __init__(self, **kwargs):
        opt = kwargs.get("opt")
        self.exp = kwargs.get("exp") 
	# self.ondisk = opt.ondisk    # TBD: PolarDB (PG) does not have an option for ondisk or inmem. But this feature can be implemented using Ramdisk
        self.server_configs, self.servermap = config_parser(opt.server_configs)
        # self.workload = opt.workload  # the scale factor of pgbench: workload * 1000
        self.pgbench_scalefactor = opt.pgbench_scalefactor
        self.threads = opt.threads    # thread here means the number of logical clients 
        self.runtime = opt.runtime
	# self.diagnose = opt.diagnose    # not quite sure how to acquire diagnositic information from PG or PolarDB 
        self.exp_type = "noslow" if self.exp == "noslow" else opt.exp_type
        self.trial = kwargs.get("trial")
	results_path = os.path.join(opt.output_path, "polardb_{}_{}_results".format(self.exp_type, self.threads)) # removed some params
	mkdir -p @(results_path)
	self.results_text = os.path.join(results_path, "{}_{}.txt".format(self.exp, self.trial))
	# self.diag_output = "???"

	self.masterip = self.server_configs[0]["publicip"] 
        self.followerip = self.server_configs[1]["publicip"]
	self.learnerip = self.server_configs[2]["publicip"]
        self.slowdownip = None

    def polar_data_cleanup(self):
        pass

    def init(self):
        # disk is automatically mounted during setup_servers stage, we omit the procedure here.
	# currently nothing has to be done in this function
	pass

    # start_db uses pgxc_ctl on the master node to initiate the cluster
    def start_db(self):
        self.polar_cleanup()
        # ssh @(self.masterip) "pgxc_ctl -c ~/polardb/paxos_multi.conf clean all"
        ssh @(HOSTID)@@(self.masterip) "pgxc_ctl -c ~/polardb/paxos_multi.conf init force all"
        ssh @(HOSTID)@@(self.masterip) "psql -p 10001 -d postgres -c 'create database pgbench;'"

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
        ssh @(HOSTID)@@(self.masterip) @("pgbench -i -s {} -p 10001 -d pgbench".format(self.pgbench_scalefactor))

    def pgbench_run(self):
        ssh @(HOSTID)@@(self.masterip) "rm -rf ~/trial* ~/Trial"


        tmp_out = $(ssh @(HOSTID)@@(self.masterip) @("pgbench -M prepared -r -c {} -j 1 -T {} -p 10001 -d pgbench -l --log-prefix=trial | tail -n22".format(self.threads, self.runtime))) 
        ssh @(HOSTID)@@(self.masterip) "cat trial* > Trial"
        num_tran = int($(ssh @(HOSTID)@@(self.masterip) "cat Trial* | wc").split()[0])
 
        # P99 calculation
        p99 = float($(ssh @(HOSTID)@@(self.masterip) @("sort ~/Trial* -k3rn|head -n {} |tail -n 1".format(int(num_tran/100)))).split()[2])

        p99_9 = float($(ssh @(HOSTID)@@(self.masterip) @("sort ~/Trial* -k3rn|head -n {} |tail -n 1".format(int(num_tran/1000)))).split()[2])
        p50 = float($(ssh @(HOSTID)@@(self.masterip) @("sort ~/Trial* -k3rn|head -n {} |tail -n 1".format(int(num_tran/2)))).split()[2])
        
        result_gen(self.results_text, tmp_out, self.exp_type, self.exp, p99_9, p99, p50)

        
    def mdiag(self):
        pass
    def copy_diag(self):
        pass
    def polar_cleanup(self):
        ssh @(HOSTID)@@(self.masterip) "pgxc_ctl -c ~/polardb/paxos_multi.conf clean all"

    # clean up the slowness config8
    def server_cleanup(self):
        ssh @(HOSTID)@@(self.masterip) "sudo sh -c 'sudo /sbin/tc qdisc del dev eth0 root; true'"
        ssh @(HOSTID)@@(self.masterip) "sudo cgdelete cpu:db cpu:cpulow cpu:cpuhigh blkio:db memory:db; true"

    def init_script(self):
        pass
    def run(self):
        start_servers(self.server_configs)
        sleep 30
        self.server_cleanup()
        # self.init()
        self.start_db()
        self.db_init()
        self.pgbench_load()
        
        #if self.exp_type != "noslow" and self.exp !="noslow":
        #    self.slowdownpids = $(ssh @(HOSTID)@@(self.slowdownip) "pgrep postgres")
        #    slow_inject(self.exp, HOSTID, self.slowdownip, self.slowdownpids)
        
        self.pgbench_run()

        self.polar_cleanup()
        self.server_cleanup()
        stop_servers(self.server_configs)
    
    def cleanup(self):
        start_servers(self.server_configs)
        self.server_cleanup()
        self.polar_cleanup()
        stop_servers(self.server_configs)
