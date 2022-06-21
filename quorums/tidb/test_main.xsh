#!/usr/bin/env xonsh

import sys
import json
import yaml
import logging
import tempfile

from utils.common_utils import *
from structures.quorum import Quorum
from faults.fault_inject import fault_inject

class TiDB(Quorum):
    def __init__(self, *args,**kwargs):
        super().__init__(*args, **kwargs)
        tikv_servers = []
        self.pd = None
        for nodes in self.nodes:
            if node.server_type == "tikv_servers":
                tikv_servers.append(node)
            elif node.server_type == "pd_server":
                self.pd = node

        self.nodes = tikv_servers

    def setup(self, storage_type):
        super().start()
        super().server_setup(storage_type)
        self.config_yaml()
        self.initialize()
        sleep 30
        self.db_init()
        self.set_node_pids()


    def config_yaml(self):
        config_data = {}
        config_data["global"] = {"user": "tidb","ssh_port": 22}
        config_data["server_configs"] = {"pd": {"replication.enable-placement-rules": true,"replication.location-labels": ["dc","rack","zone","host"],"schedule.tolerant-size-ratio": 20}}
        config_data["pd_servers"] = [{"host": self.pd.ip, "deploy_dir": self.pd.data_dir, "data_dir": self.pd.data_dir}]
        config_data["tikv_servers"] = []
        for node in self.nodes:
            config_data["tikv_servers"].aapend({"host": node.ip, "deploy_dir": node.data_dir, "data_dir": node.data_dir, "port": 20160 + node.port_offset, "status_port": 20180 + node.port_offset,
                "config": {
                    "server.labels": {
                        "dc": "1",
                        "zone": "1",
                        "rack": "1",
                        "host": "30"
                    },
                    "raftstore.raft-min-election-timeout-ticks": 1000,
                    "raftstore.raft-max-election-timeout-ticks": 1200
                }
            })
        config_data["monitoring_servers"] = [{"host": self.pd.ip}]
        config_data["grafana_servers"] = [{"host": self.pd.ip}]
        config_data["alertmanager_servers"] = [{"host": self.pd.ip}]

        self.setup_yaml = tempfile.NamedTemporaryFile(suffix=".yaml")
        with open(self.setup_updt_yaml, "w") as f:
            yaml.dump(config_data, f)
    
    def initialize(self):
        scp self.setup_updt_yaml @(self.pd.ip):~/
        self.pd.run(f"{self.pd.tiup} cluster deploy mytidb v4.0.0 ~/setup_updt.yaml --user tidb -y")
        
        for node in self.nodes:
            run_tikv = os.path.join(node.data_dir, "scripts/run_tikv.sh")
            node.run(f"sudo sed -i 's#bin/tikv-server#taskset -ac {node.cpu_affinity} bin/tikv-server#g' {run_tikv}")
        
        self.pd.run(f"{self.pd.tiup} cluster start mytidb")

    def db_init(self):
        tiup ctl:v4.0.0 pd config set label-property reject-leader dc 1 -u @(f"http://{self.pd.ip}:2379")    # leader is restricted to s3
        sleep 10

    def get_cluster(self, node_type):
        return self.nodes[0] ##tidb doesn't follow traditional master slave arch, update accordingly

    def get_leader(self):
        return self.get_cluster("leader")

    def get_follower(self):
        return self.get_cluster("follower")

    def set_node_pids(self):
        for node in self.nodes:
            pids = node.run("sh -c 'pgrep tikv-server'").split()
            all_pids = []
            for pid in pids:
                affinity = node.run(f"sh -c 'taskset -pc {pid}'")
                if node.cpu_affinity == ac.split(": ")[1]:
                    all_pids.append(pid)
                    
            setattr(node, "pids", all_pids)

    # benchmark_load is used to run the ycsb load and wait until it completes.
    def benchmark_load(self, clients, workload, exp_type, *args, **kwargs):
        taskset -ac @(self.client_configs['cpu_affinity']) @(self.client_configs["ycsb"]) load tikv -P @(workload) -p tikv.pd=@(self.pd.ip):2379 -threads=@(clients)

    # ycsb run exectues the given workload and waits for it to complete
    def benchmark_run(self, clients, workload, exp_type, runtime, output_path, *args, **kwargs):
        taskset -ac @(self.client_configs['cpu_affinity']) @(self.client_configs["ycsb"]) run tikv -P @(workload) -p maxexecutiontime=@(runtime) -p tikv.pd=@(self.pd.ip):2379 -threads=@(clients) > @(output_path)

    
    def tidb_cleanup(self):
        self.pd.run(f"{self.pd.tiup} cluster destroy mytidb -y")
