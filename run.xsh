#!/usr/bin/env xonsh

import yaml
import argparse
from threading import Timer
from easydict import EasyDict as edict

from tests.tidb.test_main import *
from tests.mongodb.test_main import *
from tests.rethink.test_main import *
from tests.copilot.test_main import *
from utils.monitor import monitor
from utils.slooo_logger import SloooLogger
from faults.fault_inject import fault_inject

logger = SloooLogger(__name__, log_prefix="[run]")

def parse_opt():
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-configs", type=str, help="path to the run config file")
    parser.add_argument("--cleanup", action='store_true', help="clean's up the servers")
    opt = parser.parse_args()
    return opt

def main(opt):
    run_configs = None
    with open(opt.run_configs) as conf:
        run_configs = edict(yaml.safe_load(conf))

    storage_type = run_configs.get("storage_type", "disk")
    exp_type = run_configs.get("exp_type", ["follower"])
    workload = run_configs.get("workload")
    run_time = run_configs.get("run_time", 300)
    output_dir = run_configs.get("output_dir")
    fault_snooze = float(run_configs.get("run_configs"))
    monitor_interval = float(run_configs.get("monitor_interval"))

    node_configs = None
    with open(run_configs.node_configs) as conf:
        node_configs = edict(yaml.safe_load(node_configs))

    server_nodes = [Nodes(config) for config in node_configs.server]
    client_configs = node_configs.client

    if opt.system == "mongodb":
        quorum = MongoDB(server_nodes=server_nodes, client_configs=client_configs)
    elif opt.system == "rethinkdb":
        quorum = RethinkDB(server_nodes=server_nodes, client_configs=client_configs)
    elif opt.system == "tidb":
        quorum = TiDB(server_nodes=server_nodes, client_configs=client_configs)
    elif opt.system == "copilot":
        quorum = Copilot(server_nodes=server_nodes, client_configs=client_configs)

    if opt.cleanup:
        quorum.server_cleanup()
        return

    configs = [
        run_configs.exp_type,
        run_configs.exps,
        run_configs.clients,
        list(range(1,run_configs.trials+1)),
    ]

    for exp_type, (exp, slownesses), clients, trial in itertools.product(*configs):
        for slowness in slownesses:
            trial_path = os.path.join("output_dir", f"{exp_type}_{exp}_{slowness}_{clients}_{trial}")
            logger.info(f"Starting trial: {trial} exp_type: {exp_type} clients: {clients} exp:{exp} slowness: {slowness})")
            quorum.setup(storage_type)
            logger.info("Setup done.")
            monitor_processes = monitor(server_nodes, quorum, trial_path)
            quorum.benchmark_load(clients, workload, exp_type)
            logger.info("Benchmark load done.")
            if exp_type == "leader":
                t = Timer(fault_snooze, fault_inject, [quorum.get_leader(), exp, slowness])
            else:
                t = Timer(fault_snooze, fault_inject, [quorum.get_follower(), exp, slowness])
            t.start()

            logger.info("Fault Injected")
            quorum.benchmark_run(clients, workload, exp_type, run_time, os.path.join(trial_path, "benchmark.txt"))
            quorum.teardown()
            for process in monitor_processes:
                process.join()
            logger.info("Done")




if __name__ == "__main__":
    opt = parse_opt()
    main(opt)
