#!/usr/bin/env xonsh

import os
import yaml
import logging
import argparse
import itertools
from typing import List, Union
from threading import Timer
from easydict import EasyDict as edict

from utils import slooo_logger
from structures.node import Node
from utils.monitor import monitor
from structures.quorum import Quorum
from quorums.tidb.test_main import *
from quorums.mongodb.test_main import *
from quorums.rethink.test_main import *
from utils.common_utils import pid_status
from faults.fault_inject import fault_inject

slooo_logger.setup_logs()
slooo_logger.update_log_level("info")

def parse_opt():
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-configs", type=str, help="path to the run config file")
    parser.add_argument("--cleanup", action='store_true', help="clean's up the servers")
    opt = parser.parse_args()
    return opt

def crash_check(nodes: List[Node]):
    crashed = False
    for node in nodes:
        for pid in node.pids:
            if not pid_status(pid):
                crashed = True
                break

    return crashed

def create_cgroups(nodes):
    for node in nodes:
        logging.info(f"Cgroup to {node}")
        node.run(f"sudo sh -c 'sudo mkdir /sys/fs/cgroup/memory/{node.name}'", True)
        node.run(f"sudo sh -c 'sudo mkdir /sys/fs/cgroup/cpu/{node.name}'", True)
        for pid in node.pids:
            node.run(f"sudo sh -c 'sudo echo {pid} > /sys/fs/cgroup/memory/{node.name}/cgroup.procs'", True)
            node.run(f"sudo sh -c 'sudo echo {pid} > /sys/fs/cgroup/cpu/{node.name}/cgroup.procs'", True)

def single_run(quorum: Quorum, 
               exp_type: str, 
               fault: str, 
               slowness: Union[int, str], 
               clients: int, 
               trial: int,
               storage_type: str,
               workload: str,
               output_dir: str,
               fault_snooze: int,
               monitor_interval: int, 
               run_time: int):
    trial_path = os.path.join(output_dir, f"{exp_type}_{fault}_{slowness}_{clients}_{trial}")
    mkdir -p @(trial_path)
    logging.info(f"Starting trial: {trial} exp_type: {exp_type} clients: {clients} fault:{fault} slowness: {slowness})")
    quorum.setup(storage_type)
    create_cgroups(quorum.nodes)
    logging.info("Setup done.")
    sleep 5
    monitor_processes = monitor(quorum, trial_path, monitor_interval)
    quorum.benchmark_load(clients, workload, exp_type)
    logging.info("Benchmark load done.")
    logging.info(f"Leader {quorum.get_leader()}")
    sleep 15
    fault_proc = None
    logging.info(f"Fault Snooze: {fault_snooze}")
    if fault != "noslow":
        fault_proc = Timer(int(fault_snooze), fault_inject, [quorum.get_cluster(exp_type), fault, slowness])
        fault_proc.start()

    sleep 5
    quorum.benchmark_run(clients, workload, exp_type, run_time, os.path.join(trial_path, "benchmark.txt"))
    sleep 10
    quorum.teardown()
    for process in monitor_processes:
        process.join()
    if fault_proc:
        fault_proc.join()
    logging.info("Done")

def main(opt):
    run_configs = None
    with open(opt.run_configs) as conf:
        run_configs = edict(yaml.safe_load(conf))

    node_configs = None
    with open(run_configs.node_configs_path) as conf:
        node_configs = edict(yaml.safe_load(conf))

    server_nodes = [Node(config) for config in node_configs.servers]
    client_configs = node_configs.client

    if run_configs.system == "mongodb":
        quorum = MongoDB(nodes=server_nodes, client_configs=client_configs)
    elif run_configs.system == "rethinkdb":
        quorum = RethinkDB(nodes=server_nodes, client_configs=client_configs)
    elif run_configs.system == "tidb":
        quorum = TiDB(nodes=server_nodes, client_configs=client_configs)

    if opt.cleanup:
        quorum.server_cleanup()
        return

    storage_type = run_configs.get("storage_type", "disk")
    exp_type = run_configs.get("exp_type", ["follower"])
    workload = run_configs.get("workload")
    run_time = run_configs.get("run_time", 300)
    output_dir = run_configs.get("output_dir")
    fault_snooze = float(run_configs.get("fault_snooze"))
    monitor_interval = float(run_configs.get("monitor_interval"))

    configs = [
        run_configs.exp_type,
        run_configs.faults,
        run_configs.clients,
        list(range(1,run_configs.trials+1)),
    ]

    for exp_type, (fault, slownesses), clients, trial in itertools.product(*configs):
        for slowness in slownesses:
            single_run(quorum, exp_type, fault, slowness, clients, trial, storage_type, workload, output_dir, fault_snooze, monitor_interval, run_time)
            sleep 5




if __name__ == "__main__":
    opt = parse_opt()
    main(opt)
