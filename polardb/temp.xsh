#!/usr/bin/env xonsh

import json
import logging
import argparse

from polardb.result_gen import *
from utils.general import *
from utils.constants_polar import *
from resources.slowness.slow import slow_inject

class PolarDB:
    def __init__(self, **kwargs):
        opt = kwargs.get("opt")
        self.exp = kwargs.get("exp") 
	# self.ondisk = opt.ondisk    # TBD: PolarDB (PG) does not have an option for ondisk or inmem. But this feature can be implemented using Ramdisk
        self.server_configs, self.servermap = config_parser(opt.server_configs)[0:2]
        # self.workload = opt.workload  # the scale factor of pgbench: workload * 1000
        self.pgbench_scalefactor = opt.pgbench_scalefactor
        self.threads = opt.threads    # thread here means the number of logical clients 
        self.runtime = opt.runtime
        self.diagnose = opt.diagnose    # not quite sure how to acquire diagnositic information from PG or PolarDB 
        self.exp_type = "noslow" if self.exp == "noslow" else opt.exp_type
        self.trial = kwargs.get("trial")
	self.results_path = os.path.join(opt.output_path, "polardb_{}_{}_results".format(self.exp_type, self.threads)) # removed some params
	mkdir -p @(self.results_path)
	self.results_text = os.path.join(self.results_path, "{}_{}.txt".format(self.exp, self.trial))
	# self.diag_output = "???"
        self.swap = True if self.exp == "6" else False
	self.masterip = self.server_configs[0]["privateip"] 
        self.followerip = self.server_configs[1]["privateip"]
	self.learnerip = self.server_configs[2]["privateip"]
        self.slowdownip = None

        self.datapath = "/home/{}/data1".format(HOSTID)
        self.datapath_db = os.path.join(self.datapath, "polardb-data")

    def polar_data_cleanup(self):
	data_cleanup(self.server_configs, self.datapath_db)

    def init(self):
        init_disk(self.server_configs, self.datapath_db, "/dev/sdc1", "xfs", self.exp, 1000, 1400000)    
	for server_config in self.server_configs:
	    ssh  @(HOSTID)@@(server_config["privateip"]) @("sh -c  'mkdir -p {}'".format(self.datapath_db)) 

	set_swap_config(self.server_configs, self.swap, self.datapath + "/swapfile", 1024, 20485790)

    # start_db uses pgxc_ctl on the master node to initiate the cluster
    def start_db(self):
        self.polar_cleanup()

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
        
        result_gen(self.results_text, tmp_out, self.exp_type, self.exp, p99_9, p99, p50) #TODO use varshith's plot function

        
    def mdiag(self):
        pass
    def copy_diag(self):
        for server_config in self.server_configs:
           # scp -r @(HOSTID)@@(server_config["privateip"]):/data1/polardb-data
            pass #TODO where are the log files of polardb datanote?
	    
    def polar_cleanup(self):
        ssh @(HOSTID)@@(self.masterip) "pgxc_ctl -c ~/polardb/paxos_multi.conf clean all"

    # clean up the slowness config
    def server_cleanup(self):
        ssh @(HOSTID)@@(self.masterip) "sudo sh -c 'sudo /sbin/tc qdisc del dev eth0 root; true'"
        ssh @(HOSTID)@@(self.masterip) "sudo cgdelete cpu:db cpu:cpulow cpu:cpuhigh blkio:db memory:db; true"

    def init_script(self):
        pass
    def run(self):
        start_servers(self.server_configs)
        sleep 30
        self.server_cleanup()
        self.init()
        self.start_db()
        self.db_init()
        self.pgbench_load()
        
        if self.exp_type != "noslow" and self.exp !="noslow":
            self.slowdownpids = $(ssh @(HOSTID)@@(self.slowdownip) "pgrep postgres")
            slow_inject(self.exp, HOSTID, self.slowdownip, self.slowdownpids)
        
        self.pgbench_run()
        
	if self.diagnose:
	    self.copy_diag()
        print("=====================================================YESYESYESYES====================")
        self.polar_cleanup()
        print("=====================================================NONONONONONO====================")
        self.server_cleanup()
        print("=====================================================fuckfuckfuck====================")
        stop_servers(self.server_configs)
        print("=====================================================yes hahah ha====================")
    
    def cleanup(self):
        start_servers(self.server_configs)
        self.server_cleanup()
        self.polar_cleanup()
        stop_servers(self.server_configs)
