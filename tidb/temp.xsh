#!/usr/bin/env xonsh

import json
import logging
import argparse
import sys

from utils.general import *
from utils.constants import *

class TiDB:
    def __init__(self, **kwargs):
        opt = kwargs.get("opt")
        self.ondisk = opt.ondisk
        self.server_configs, self.servermap, nodes = config_parser(opt.server_configs)
		self.pd_node = nodes["pd"][0]
        self.workload = opt.workload
        self.threads = opt.threads
        self.runtime = opt.runtime
        self.diagnose = opt.diagnose
        self.exp = kwargs.get("exp")
        self.swap = True if self.exp == "6" else False
        self.exp_type = "noslow" if self.exp == "noslow" else opt.exp_type
        self.trial = kwargs.get("trial")
        results_path = os.path.join(opt.output_path, "tidb_{}_{}_{}_{}_results".format(self.exp_type,"swapon" if self.swap else "swapoff", self.ondisk, self.threads))
        mkdir -p @(results_path)
        self.results_txt = os.path.join(results_path,"{}_{}.txt".format(self.exp,self.trial))

    def tidb_data_cleanup(self):
		data_cleanup(self.server_configs, "/data1")

	def init(self):
		init_disk(self.server_configs, "/data1","/dev/sdc1", self.exp, "ext4", 1000, 1400000)
        set_swap_config(self.server_configs, self.swap, "/data1/swapfile", 1024, 25165824)

	def start_db(self):
		if self.exp_type == "follower" or self.exp_type == "noslow2":
			tiup cluster deploy mytidb v4.0.0 ./tidb_restrict_hdd.yaml --user tidb -y
		else:
			tiup cluster deploy mytidb v4.0.0 ./tidb_hdd.yaml --user tidb -y

		for server_config in self.server_configs:
			scp ~/tikv-server @(HOSTID)@@(server_config["privateip"]):/data1/tidb-deploy/tikv-20160/bin/

		for server_config in self.server_configs:
			ssh -i ~/.ssh/id_rsa @(HOSTID)@@(server_config["privateip"]) "sudo sed -i 's#bin/tikv-server#taskset -ac 0 bin/tikv-server#g' /data1/tidb-deploy/tikv-20160/scripts/run_tikv.sh"

		tiup cluster start mytidb
  		sleep 30

	def db_init(self):
		if self.exp_type=="follower" or self.exp_type=="noslow2":
    		tiup ctl pd config set label-property reject-leader dc 1 -u http://@(self.pd_node["privateip"]):2379     # leader is restricted to s3
    		sleep 10

		if self.exp_type=="follower":
			followerip=self.server_configs[0]["privateip"]
			followerpid=$(ssh -i ~/.ssh/id_rsa @(HOSTID)@@(followerip) "pgrep tikv-server")
			self.slowdownpid=followerpid
			self.slowdownip=followerpid

		###########NEEDS TO BE ADDRESSED###############
		elif self.exp_type=="leaderlow":
			leaderip=$(python3 getleader.py $pd min)
			leaderpid=$(ssh -i ~/.ssh/id_rsa tidb@"$leaderip" "pgrep tikv-server")
			self.slowdownpid=leaderpid
			self.slowdownip=leaderip
		elif self.exp_type=="leaderhigh":
			leaderip=$(python3 getleader.py $pd max)
			leaderpid=$(ssh -i ~/.ssh/id_rsa tidb@"$leaderip" "pgrep tikv-server")
			self.slowdownpid=leaderpid
			self.slowdownip=leaderip


	# ycsb_load is used to run the ycsb load and wait until it completes.
    def ycsb_load(self):
		@(YCSB) load tikv -P @(self.workload) -p tikv.pd=@(self.pd_node["privateip"]):2379 --threads=@(self.threads)

	# ycsb run exectues the given workload and waits for it to complete
	def ycsb_run(self):
		@(YCSB)	run tikv -P @(self.workload) -p maxexecutiontime=@(self.runtime) -p tikv.pd=@(self.pd_node["privateip"]):2379 --threads=@(self.threads) > @(self.results_txt)

	
	def tidb_cleanup(self):
		tiup cluster destroy mytidb -y
	
	def server_cleanup(self):
        cleanup(self.server_configs, "/data1","/dev/sdc1", "dd", self.swap, "/data1/swapfile")


	def run(self):
        start_servers(self.server_configs + [self.pd_node])
        sleep 30
        
		self.tidb_data_cleanup()
        self.server_cleanup()
        
		self.init()
        self.start_db()
        self.db_init()   
        
		self.ycsb_load()
        
        if self.exp_type != "noslow" and self.exp != "noslow":
            slow_inject(self.exp, HOSTID, self.slowdownip, self.slowdownpid)

        self.ycsb_run()

		###ADDING OPTION TO IMPORT TIDB LOGS

        self.tidb_cleanup()
        self.server_cleanup()
		self.tidb_data_cleanup()
        
		stop_servers(self.server_configs + [self.pd_node])


    def cleanup(self):
        start_servers(self.server_configs + [self.pd_node])
        self.server_cleanup()
        self.tidb_data_cleanup()
        stop_servers(self.server_configs + [self.pd_node])