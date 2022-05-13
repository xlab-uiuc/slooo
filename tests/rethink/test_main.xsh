#!/usr/bin/env xonsh

import logging
from rethinkdb import r

from utils.quorum import Quorum
from utils.slooo_logger import SloooLogger

logger = SloooLogger(__name__, log_prefix="[rethinkdb]")

class RethinkDB(Quorum):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)

    def setup(self, *args, **kwargs):
        super.start()
        super().server_setup()

    def initialize(self):
        cluster_node = None
        for idx, node in enumerate(self.nodes):
            if idx==0:
                node.run(f"sh -c 'taskset -ac {node.cpu_affinity} rethinkdb --directory {node.data_dir} --port-offset {node.port_offset} --bind all --server-name {node.name} --daemon'")
                cluster_node = node
            else:
                node.run(f"sh -c 'taskset -ac {node.cpu_affinity} rethinkdb --directory {node.data_dir} --port-offset {node.port_offset} --join {node.ip}:{29015+node.port_offset} --bind all --server-name {node.name} --daemon'")

    def db_init(self):
        self.pyserver = self.nodes[0]
        logger.info("connecting to server {pyserver}")
        r.connect(pyserver.ip, pyserver.port_offset + 28015)
        logger.info("Connection established")
        try:
            r.db("ycsb").table_drop("usertable").run()
        except Exception as e:
            logger.info(f"Could not delete usertable {e}")

        try:
            r.db_drop("ycsb").run()
        except Exception as e:
            logger.info(f"Could not delete db {e}")

        try:
            r.db_create("ycsb").run()
            r.db("ycsb").table_create("usertable", replicas=len(self.server_configs),primary_key="__pk__").run()
        except Exception as e:
            logger.error(f"Could not create table {e}")

        sleep 5


    def get_cluster(self, node_type): ###rename the function
        table_status = list(r.db('rethinkdb').table('table_status').run())
        primaryreplica = table_status[0]['shards'][0]['primary_replicas'][0]

        replicas = table_status[0]['shards'][0]['replicas']
        secondaryreplica = None
        for rep in replicas:
            if rep['server'] != primaryreplica:
                secondaryreplica = rep['server']
                break


        server_status = list(r.db('rethinkdb').table('server_status').run())
        namePidRes = [(n['name'],n['process']['pid']) for n in server_status]

        leader = None
        follower = None
        for p in namePidIpRes:
            if p[0] == primaryreplica:
                for node in self.nodes:
                    if node.name == primaryreplica:
                        node.ips = str(p[1])
                        leader = node
                    break
            if p[0] == secondaryreplica:
                for node in self.nodes:
                    if node.name == primaryreplica:
                        node.ips = str(p[1])
                        follower = node
                    break

        return leader if node_type == "leader" elif follower if node_type == "follower"

    def get_leader(self):
        return self.get_cluster("leader")

    def get_follower(self):
        return self.get_cluster("follower")

    # benchmark_load is used to run the ycsb load and wait until it completes.
    def benchmark_load(self, clients, workload, exp_type, *args, **kwargs):
        if exp_type == "leader":
            self.pyserver = self.get_follower()
        elif exp_type == "follower":
            self.pyserver = self.get_leader()
        @(self.client_configs["ycsb"]) load rethinkdb -s -P @(workload) -p rethinkdb.host=@(pyserver.ip) -p rethinkdb.port=@(pyserver.port_offset+28015) -threads @(clients)

    # ycsb run exectues the given workload and waits for it to complete
    def benchmark_run(self, clients, workload, exp_type, run_time, output_path, *args, **kwargs):
        @(self.client_configs["ycsb"]) run rethinkdb -s -P @(workload) -p maxexecutiontime=@(runtime) -p rethinkdb.host=@(self.pyserver.ip) -p rethinkdb.port=@(self.pyserver.port_offset+28015) -threads @(clients) > @(output_path)

    def db_cleanup(self):
        logger.info(f"connecting to server {self.pyserver}")
        r.connect(self.pyserver.ip, self.pyserver.port_offset+28015)
        logger.info("Connection established")
        try:
            r.db("ycsb").table_drop("usertable").run()
        except Exception as e:
            logger.error(f"Could not delete usertable {e}")

        try:
            r.db_drop("ycsb").run()
        except Exception as e:
            logger.error(f"Could not delete db {e}")


    def teardown(self):
        self.db_cleanup()
        super.server_cleanup()
