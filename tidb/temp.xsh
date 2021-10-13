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

    def init(self):
        super().server_setup()

    def setup_yaml(self):
        data = None
        with open(self.setup_yaml, "r") as f:
            data = f.read()
        
        data.replace("<pd_host>", self.pd_configs["private_ip"])
        data.replace("<pd_deploy_dir>", self.pd_configs["deploy_dir"])
        data.replace("<pd_deploy_dir>", self.pd_configs["deploy_dir"])

        for idx, server_config in enumerate(self.server_configs):
            ip = server_config["privateip"]
            deploy_dir = server_config["deploy_dir"]
            data_dir = server_config["data_dir"]
            port_offset = server_config["port_offset"]
            data.replace(f"s{idx}_host", ip)
            data.replace(f"s{idx}_deploy_dir", deploy_dir)
            data.replace(f"s{idx}_data_dir", data_dir)
            data.replace(f"s{idx}_port", str(20160 + port_offset))
            data.replace(f"s{idx}_status_port", str(20180 + port_offset))

        with open(self.setup_updt_yaml, "w") as f:
            f.write(data)
    
    def start_db(self):
        pd_ip = self.pd_configs["privateip"]
        ssh -i ~/.ssh/id_rsa @(pd_ip) @(f"tiup cluster deploy mytidb v4.0.0 {self.setup_updt_yaml} --user tidb -y")

        for server_config in self.server_configs:
            ip = server_config["privateip"]
            deploy_dir = server_config["deploy_dir"]
            run_tikv = os.path.join(deploy_dir, "scripts/run_tikv.sh")
            cpu = server_config["cpu"]
            ssh -i ~/.ssh/id_rsa @(ip) @(f"sudo sed -i 's#bin/tikv-server#taskset -ac {cpu} bin/tikv-server#g' {run_tikv}")

        ssh -i ~/.ssh/id_rsa @(pd_ip) "tiup cluster start mytidb"
        sleep 30

    def db_init(self):
        pd_ip = self.pd_configs["privateip"]
        ssh -i ~/.ssh/id_rsa @(pd_ip) @(f"tiup ctl pd config set label-property reject-leader dc 1 -u http://{pd_ip}:2379")    # leader is restricted to s3
        sleep 10

        followerip=self.server_configs[0]["privateip"]
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
        client_ycsb = self.client_configs["ycsb"]
        @(client_ycsb) load tikv -P @(self.workload) -p tikv.pd=@(self.pd_node["privateip"]):2379 --threads=@(self.threads)

    # ycsb run exectues the given workload and waits for it to complete
    def ycsb_run(self):
        client_ycsb = self.client_configs["ycsb"]
        @(client_ycsb) run tikv -P @(self.workload) -p maxexecutiontime=@(self.runtime) -p tikv.pd=@(self.pd_node["privateip"]):2379 --threads=@(self.threads) > @(self.results_txt)

    
    def tidb_cleanup(self):
        pd_ip = self.pd_configs["privateip"]
        ssh -i ~/.ssh/id_rsa @(pd_ip) tiup cluster destroy mytidb -y
    
    def server_cleanup(self):
        super().server_cleanup()    


    def run(self):
        start_servers(self.server_configs + [self.pd_node])
        self.setup_yaml()
        
        # self.tidb_data_cleanup()
        self.server_cleanup()
        
        self.init()
        self.start_db()
        self.db_init()   
        
        self.ycsb_load()
        
        if self.exp_type != "noslow" and self.exp != "noslow":
            slow_inject(self.exp, HOSTID, self.slowdownip, self.slowdownpid)

        self.ycsb_run()

        self.tidb_cleanup()
        self.server_cleanup()
        
        stop_servers(self.server_configs + [self.pd_node])


    def cleanup(self):
        start_servers(self.server_configs)
        self.server_cleanup()
        self.tidb_data_cleanup()
        stop_servers(self.server_configs)