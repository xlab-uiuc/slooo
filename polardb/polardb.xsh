#!/usr/bin/env xonsh

import json
import logging
import argparse

from utils.general import *
# from utils.constants import *
from resources.slowness.slow import slow_inject

class PolarDB:
    def __init__(self, **kwargs):
        opt = kwargs.get("opt")
        
	# self.ondisk = opt.ondisk    # TBD: PolarDB (PG) does not have an option for ondisk or inmem. But this feature can be implemented using Ramdisk
        self.server_configs, self.servermap = config_partser(opt.server_configs)
        self.workload = opt.workload  # the scale factor of pgbench: workload * 1000
        self.threads = opt.threads    # thread here means the number of logical clients 
        self.runtime = opt.runtime
	# self.diagnose = opt.diagnose    # not quite sure how to acquire diagnositic information from PG or PolarDB 
        self.exp_type = "noslow" if self.exp == "noslow" else opt.exp_type
        self.trial = kwargs.get("trial")
	results_path = os.path.join(opt.output_path, "polardb_{}_{}_{}_results".format(self.exp_type, self.clients, self.threads) # removed some params
	mkdir -p @(results_path)
	self.results_text = os.path.join(results.path, "{}_{}.txt".format(self.exp, self.trial))
	# self.diag_output = "???"
	self.init_script_path = 
	self.fetchprimary_path = 
	self.cleanup_script_path =

	self.masterip = None
        self.masterpid = None    # pid parameters should be an array for polardb
        self.followerip = None
	self.followerpid = None
	self.learnerip = None
	self.learnerpid = None
        self.slowdownip = None
    def polar_data_cleanup(self):

    def init(self):
        # disk is automatically mounted during setup_servers stage, we omit the procedure here.
	# currently nothing has to be done in this function
	pass

    # start_db uses pgxc_ctl on the master node to initiate the cluster
    def start_db(self):i
        polar_cleanup()
        # ssh @(self.masterip) "pgxc_ctl -c ~/polardb/paxos_multi.conf clean all"
        ssh @(self.masterip) "pgxc_ctl -c ~/polardb/paxos_multi.conf init force all"
        ssh @(self.masterip) "psql -p 10001 -d postgres -c 'create database pgbench;'"

    def db_init(self):
        if self.exp_type == "leader":
	    self.slowdownip = self.masterip
	elif self.exp_type == 
    def pgbench_load(self):
    def pgbench_run(self):
    def mdiag(self):
    def copy_diag(self):
    def polar_cleanup(self):
    def server_cleanup(self):
    def init_script(self):
    def run(self):
    def cleanup(self):

