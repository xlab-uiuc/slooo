#!/usr/bin/env xonsh

import logging

from utils.quorum import Quorum
from utils.common_utils import *
from faults.fault_inject import fault_inject

class Copilot(Quorum):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.master_configs = self.nodes["master"]
        self.results_path = os.path.join(self.output_path, "copilot_{}_{}_{}_{}_results".format(self.exp_type,"swapon" if self.swap else "swapoff", self.ondisk, self.threads))
        mkdir -p @(self.results_path)

    def server_cleanup(self):
        for cfg in self.server_configs + [self.master_configs]:
            ssh -i ~/.ssh/id_rsa @(cfg["ip"]) @(f"sudo sh -c 'pkill {cfg['process']}'")

    def start_db(self):
        ssh -i ~/.ssh/id_rsa @(self.master_configs["ip"]) @(f"sh -c '{self.master_configs['master']} -N={len(self.server_configs)} -twoLeaders={self.master_configs['doTwoLeaders']}'")

        for cfg in self.server_configs:
            ssh -i ~/.ssh/id_rsa @(cfg["ip"]) @(f"sh -c 'numactl --interleave=all taskset -ac {cfg['cpu']} {cfg['server']} -maddr={self.master_configs['ip']} -mport={self.master_configs['port']} -addr={cfg['ip']} -port={cfg['port']} -copilot=true -exec=true -dreply=true -durable=false -p=1 -thrifty=false'")
            sleep 2

        sleep 5

    def db_init(self):
        pass

    def benchmark_run(self):
        for idx in enumerate(self.threads):
            @(self.client_configs["client"]) -maddr=@(self.master_configs["ip"]) -mport=@(self.master_configs["port"]) -q=1000000 -check=true -twoLeaders=true -id=@(idx)  -prefix=@(self.results_path) -runtime=@(self.runtime) &


    def run(self):
        start_servers(self.server_configs)
        
        self.server_cleanup()

        self.start_db()
        self.db_init()

        fault_inject(self.exp, self.fault_server_config, self.fault_pids)

        self.benchmark_run()

        self.server_cleanup()

        stop_servers(self.server_configs)