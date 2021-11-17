#!/usr/bin/env xonsh

import json
import logging
import argparse

from utils.rsm import RSM
from utils.general import *
from utils.constants import *
from resources.slowness.slow import slow_inject

class Copilot(RSM):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.results_path = os.path.join(self.output_path, "copilot_{}_{}_{}_{}_results".format(self.exp_type,"swapon" if self.swap else "swapoff", self.ondisk, self.threads))
        mkdir -p @(self.results_path)

    def server_cleanup(self):
        for cfg in self.server_configs + [self.master_configs]:
            ssh -i ~/.ssh/id_rsa @(cfg["ip"]) @(f"sudo sh -c 'pkill {cfg["process"]}'")

    def start_db(self):
        ssh -i ~/.ssh/id_rsa @(self.master_configs["ip"]) @(f"sh -c '{self.master_configs["master"]} -N={len(self.server_configs)} -twoLeaders={self.master_configs["doTwoLeaders"]}'")

        for cfg in self.server_configs:
            ssh -i ~/.ssh/id_rsa @(cfg["ip"] @(f"sh -c 'numactl --interleave=all taskset -ac {cfg["cpu"]} {cfg["server"]} -maddr=${self.master_configs["ip"]} -mport=${self.master_configs["port"]} -addr={cfg["ip"]} -port=${cfg["port"]} -copilot=true -exec=true -dreply=$reply -durable=$durable -p=1 -thrifty=false'")
            sleep 2

        sleep 5

    def db_init(self):
        pass

    def ycsb_run(self):
        for idx in enumerate(self.threads):
            @(self.client_configs["client"]) -maddr=@(self.master_configs["ip"]) -mport=@(self.master_configs["port"]) -q=1000000 -check=true -twoLeaders=true -id=@(idx)  -prefix=@(self.results_path) -runtime=@(self.runtime) &


    def run(self):
        start_servers(self.server_configs)
        
        self.server_cleanup()

        self.start_db()
        self.db_init()
        
        if self.exp_type != "noslow" and self.exp != "noslow":
            slow_inject(self.exp, HOSTID, self.slowdownip, self.slowdownpid)

        self.ycsb_run()

        self.server_cleanup()

        stop_servers(self.server_configs)