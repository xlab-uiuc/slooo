#!/usr/bin/env xonsh

import json
import logging

from structures.quorum import Quorum
from utils.common_utils import get_cpids

class MongoDB(Quorum):
    def __init__(self, *args,**kwargs):
        super().__init__(*args, **kwargs)


    def setup(self, storage_type):
        super().start()
        super().server_setup(storage_type)
        for node in self.nodes:
            setattr(node, "host", f"{node.ip}:{node.port}")
        self.initialize()
        sleep 3
        self.db_init()
        self.set_node_pids()


    # start_db starts the database instances on each of the server
    def initialize(self):
        for node in self.nodes:
            node.run(f"sh -c 'numactl --interleave=all taskset -ac {node.cpu_affinity} {node.mongod} --replSet rs0 --bind_ip localhost,{node.name} --port {node.port} --fork --logpath {node.logpath} --dbpath {node.data_dir}'")


    def db_init(self):
        for idx,node in enumerate(self.nodes):
            members = members + f"{{_id:{idx}, host:'{node.host}'}}"
            if idx != len(self.nodes):
                members = members + ","
        init_command = f"rs.initiate( {{_id : 'rs0', members: [{members}]}})"

        @(self.client_configs["mongo"]) --host @(f"{self.nodes[0].host}") --eval @(init_command)
        
        # Wait for startup
        sleep 60

        primary_node = self.get_cluster("leader")

        # Disable chaining allowed
        @(self.client_configs["mongo"]) --host @(primary_node.host) --eval "cfg = rs.config();\
                                                         cfg.settings.chainingAllowed = false;\
                                                         rs.reconfig(cfg);"
        for node in self.nodes:
            if node.name == primary_node.name:
                continue
            @(self.client_configs["mongo"]) --host @(node.host) --eval @(f"db.adminCommand( {{ replSetSyncFrom: '{primary_node.host}'}})")

        # Set WriteConcern==majority    in order to make it consistent between all DBs
        @(self.client_configs["mongo"]) --host @(primary_node.host) --eval "cfg = rs.config();\
                                                         cfg.settings.getLastErrorDefaults = { j:true, w:'majority', wtimeout:10000 };\
                                                         rs.reconfig(cfg);"

    def set_node_pids(self):
        for node in self.nodes:
            pids = node.run("sh -c 'pgrep mongo'").split()
            all_pids = []
            for pid in pids:
                affinity = node.run(f"sh -c 'taskset -pc {pid}'")
                if node.cpu_affinity == ac.split(": ")[1]:
                    all_pids.append(pid)
                    
            setattr(node, "pids", all_pids)


    def get_cluster(self, node_type):
        client_mongo = self.client_configs["mongo"]
        fetch_command = """db.adminCommand( { replSetGetStatus: 1 } )["members"].map((member) => {return {"name": member["name"], "stateStr": member["stateStr"]};});"""

        response = $(@(client_mongo) --host @(f"{self.nodes[0].ip}:{self.nodes[0].port}") --eval @(fetch_command) | tail -n +5 | head -n -1)
        mongo_servers = json.loads(response)

        for mongo_server in mongo_servers:
            if mongo_server["stateStr"] == "PRIMARY":
                primary_server = mongo_server["name"].split(":")[0]
            elif mongo_server["stateStr"] == "SECONDARY":
                secondary_server = mongo_server["name"].split(":")[0]


        for node in self.nodes:
            if primary_server == node.name and node_type == "leader":
                return node
            elif secondary_server == node.name and node_type == "follower":
                return node

    def benchmark_load(self, clients, workload, exp_type, *args, **kwargs):
        primary_host = self.get_cluster("leader").host
        mongo_url = f"mongodb://{primary_host}/ycsb?w=majority&readConcernLevel=majority"
        taskset -ac @(self.client_configs["cpu_affinity"]) @(self.client_configs["ycsb"]) load mongodb -s -P @(workload) -threads @(clients) -p mongodb.url=@(mongo_url)

    def benchmark_run(self, clients, workload, exp_type, runtime, output_path, *args, **kwargs):
        primary_host = self.get_cluster("leader").host
        mongo_url = f"mongodb://{primary_host}/ycsb?w=majority&readConcernLevel=majority"
        taskset -ac @(self.client_configs["cpu_affinity"]) @(self.client_configs["ycsb"]) run mongodb -s -P @(workload) -threads @(clients)  -p maxexecutiontime=@(runtime) -p mongodb.url=@(mongo_url) > @(output_path)
        
    def db_cleanup(self):
        primary_host = self.get_cluster("leader").host
        @(self.client_configs["mongo"]) --host @(primary_node.host) --eval "use ycsb \n db.usertable.drop()"
        @(self.client_configs["mongo"]) --host @(primary_node.host) --eval "db.getCollectionNames().forEach(function(n){db[n].remove()});"