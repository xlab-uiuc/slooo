#!/usr/bin/env xonsh

import logging
from rethinkdb import r

from structures.quorum import Quorum
from utils.common_utils import get_cpids

class RethinkDB(Quorum):
    def __init__(self, *args,**kwargs):
        super().__init__(*args, **kwargs)

    def setup(self, storage_type):
        super().start()
        super().server_setup(storage_type)
        self.initialize()
        sleep 3
        self.db_init()
        self.set_node_pids()

    def initialize(self):
        cluster_node = None
        for idx, node in enumerate(self.nodes):
            if idx==0:
                node.run(f"sh -c 'taskset -ac {node.cpu_affinity} rethinkdb --directory {node.data_dir} --port-offset {node.port_offset} --bind all --server-name {node.name} --daemon'")
                cluster_node = node
            else:
                node.run(f"sh -c 'taskset -ac {node.cpu_affinity} rethinkdb --directory {node.data_dir} --port-offset {node.port_offset} --join {cluster_node.ip}:{29015+cluster_node.port_offset} --bind all --server-name {node.name} --daemon'")

    def db_init(self):
        self.pyserver = self.nodes[0]
        logging.info(f"connecting to server {self.pyserver}")
        conn = r.connect(self.pyserver.ip, self.pyserver.port_offset + 28015)
        logging.info("Connection established")
        try:
            r.db("ycsb").table_drop("usertable").run(conn)
        except Exception as e:
            logging.warning(f"Could not delete usertable {e}")

        try:
            r.db_drop("ycsb").run(conn)
        except Exception as e:
            logging.warning(f"Could not delete db {e}")

        try:
            r.db_create("ycsb").run(conn)
            r.db("ycsb").table_create("usertable", replicas=len(self.nodes),primary_key="__pk__").run(conn)
            r.db('rethinkdb').table('cluster_config').update({'heartbeat_timeout_secs': 2}).run(conn)
        except Exception as e:
            logging.error(f"Could not create table {e}")

    def set_node_pids(self):
        conn = r.connect(self.pyserver.ip, self.pyserver.port_offset + 28015)
        server_status = list(r.db('rethinkdb').table('server_status').run(conn))
        namePidRes = [(n['name'],n['process']['pid']) for n in server_status]

        for p in namePidRes:
            for node in self.nodes:
                if node.name == p[0]:
                    ppid = int(p[1])
                    all_pids = [ppid]
                    all_pids.extend(get_cpids(ppid))
                    setattr(node, "pids", all_pids) 


    def get_cluster(self, node_type): ###rename the function
        conn = r.connect(self.pyserver.ip, self.pyserver.port_offset + 28015)
        table_status = list(r.db('rethinkdb').table('table_status').run(conn))

        primaryreplica = table_status[0]['shards'][0]['primary_replicas'][0]

        replicas = table_status[0]['shards'][0]['replicas']
        secondaryreplica = None
        for rep in replicas:
            if rep['server'] != primaryreplica:
                secondaryreplica = rep['server']
                break


        server_status = list(r.db('rethinkdb').table('server_status').run(conn))
        namePidRes = [(n['name'],n['process']['pid']) for n in server_status]

        leader = None
        follower = None
        for p in namePidRes:
            for node in self.nodes:
                if p[0] == primaryreplica:
                    if node.name == primaryreplica:
                        leader = node
                        break
                elif p[0] == secondaryreplica:
                    if node.name == secondaryreplica:
                        follower = node
                        break

        if node_type == "leader":
            return leader
        elif node_type == "follower":
            return follower

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
        taskset -ac @(self.client_configs['cpu_affinity']) @(self.client_configs["ycsb"]) load rethinkdb -s -P @(workload) -p rethinkdb.host=@(self.pyserver.ip) -p rethinkdb.port=@(self.pyserver.port_offset+28015) -threads @(clients)

    # ycsb run exectues the given workload and waits for it to complete
    def benchmark_run(self, clients, workload, exp_type, runtime, output_path, *args, **kwargs):
        taskset -ac @(self.client_configs['cpu_affinity']) @(self.client_configs["ycsb"]) run rethinkdb -s -P @(workload) -p maxexecutiontime=@(runtime) -p rethinkdb.host=@(self.pyserver.ip) -p rethinkdb.port=@(self.pyserver.port_offset+28015) -threads @(clients) > @(output_path)

    def db_cleanup(self):
        logging.info(f"connecting to server {self.pyserver}")
        conn = r.connect(self.pyserver.ip, self.pyserver.port_offset + 28015)
        logging.info("Connection established")
        try:
            r.db("ycsb").table_drop("usertable").run(conn)
        except Exception as e:
            logging.error(f"Could not delete usertable {e}")

        try:
            r.db_drop("ycsb").run(conn)
        except Exception as e:
            logging.error(f"Could not delete db {e}")


    def teardown(self):
        self.db_cleanup()
        super().server_cleanup()
