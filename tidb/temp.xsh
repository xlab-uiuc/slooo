#!/usr/bin/env xonsh

import sys
import json
import yaml
import logging
import argparse

from utils.rsm import RSM
from utils.general import *
from utils.constants import *

class TiDB(RSM):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.pd_configs = self.nodes["pd"]
        results_path = os.path.join(self.output_path, "tidb_{}_{}_{}_{}_results".format(self.exp_type,"swapon" if self.swap else "swapoff", self.ondisk, self.threads))
        mkdir -p @(results_path)
        self.results_txt = os.path.join(results_path,"{}_{}.txt".format(self.exp,self.trial))
        self.setup_yaml = os.path.join(os.path.dirname(os.path.realpath(__file__)), "setup.yaml")
        self.setup_updt_yaml = os.path.join(os.path.dirname(os.path.realpath(__file__)), "setup_updt.yaml")

    # def tidb_data_cleanup(self):
    #     data_cleanup(self.server_configs, "/data1")

    def config_yaml(self):
        data = None
        with open(self.setup_yaml, "r") as f:
            data = f.read()
        
        data = data.replace("<pd_host>", self.pd_configs["ip"])
        data = data.replace("<pd_deploy_dir>", self.pd_configs["deploy_dir"])
        data = data.replace("<pd_data_dir>", self.pd_configs["data_dir"])

        for idx, cfg in enumerate(self.server_configs):
            data = data.replace(f"<s{idx+1}_host>", cfg["ip"])
            data = data.replace(f"<s{idx+1}_deploy_dir>", cfg["deploy_dir"])
            data = data.replace(f"<s{idx+1}_data_dir>", cfg["data_dir"])
            data = data.replace(f"<s{idx+1}_port>", str(20160 + int(cfg["port_offset"])))
            data = data.replace(f"<s{idx+1}_status_port>", str(20180 + int(cfg["port_offset"])))

        with open(self.setup_updt_yaml, "w") as f:
            f.write(data)
    
    def start_db(self):
        scp self.setup_updt_yaml @(self.pd_configs["ip"]):~/
        ssh -i ~/.ssh/id_rsa @(self.pd_configs["ip"]) @(f"{self.pd_configs["tiup"]} cluster deploy mytidb v4.0.0 ~/setup_updt.yaml --user tidb -y")

        for cfg in self.server_configs:
            run_tikv = os.path.join(cfg["deploy_dir"], "scripts/run_tikv.sh")
            ssh -i ~/.ssh/id_rsa @(cfg["ip"]) @(f"sudo sed -i 's#bin/tikv-server#taskset -ac {cfg["cpu"]} bin/tikv-server#g' {run_tikv}")

        ssh -i ~/.ssh/id_rsa @(self.pd_configs["ip"]) @(f"{self.pd_configs["tiup"]} cluster start mytidb")
        sleep 30

    def db_init(self):
        tiup ctl:v4.0.0 pd config set label-property reject-leader dc 1 -u @(f"http://{self.pd_configs["ip"]}:2379")    # leader is restricted to s3
        sleep 10

        followerip=self.server_configs[0]["ip"]
        pids=$(ssh -i ~/.ssh/id_rsa @(followerip) "sh -c 'pgrep tikv-server'")
        pids = pids.split()
        for pid in pids:
            ac = $(ssh -i ~/.ssh/id_rsa @(followerip) @(f"sh -c 'taskset -pc {pid}'"))
            if self.server_configs[0]["cpu"] ==  int(ac.split(": ")[1]):
                secondarypid = pid

        if self.exp_type=="follower":
            self.slowdownpid=secondarypid
            self.slowdownip=followerip

    # ycsb_load is used to run the ycsb load and wait until it completes.
    def ycsb_load(self):
        @(self.client_configs["ycsb"]) load tikv -P @(self.workload) -p tikv.pd=@(self.pd_configs["ip"]):2379 --threads=@(self.threads)

    # ycsb run exectues the given workload and waits for it to complete
    def ycsb_run(self):
        @(self.client_configs["ycsb"]) run tikv -P @(self.workload) -p maxexecutiontime=@(self.runtime) -p tikv.pd=@(self.pd_configs["ip"]):2379 --threads=@(self.threads) > @(self.results_txt)

    
    def tidb_cleanup(self):
        ssh -i ~/.ssh/id_rsa @(self.pd_configs["ip"]) @(f"{self.pd_configs["tiup"]} cluster destroy mytidb -y")


    def run(self):
        start_servers(self.server_configs + [self.pd_configs])
        self.config_yaml()
        
        # self.tidb_data_cleanup()
        self.server_cleanup()
        
        self.server_setup()
        self.start_db()
        self.db_init()   
        
        self.ycsb_load()
        
        if self.exp_type != "noslow" and self.exp != "noslow":
            slow_inject(self.exp, HOSTID, self.slowdownip, self.slowdownpid)

        self.ycsb_run()

        self.tidb_cleanup()
        self.server_cleanup()
        
        stop_servers(self.server_configs + [self.pd_configs])