#!/usr/bin/env xonsh

from typing import List

from utils.node import Node
from utils.common_utils import *

class Quorum:
    storage_type: str = "disk"
    server_nodes: List[Nodes] = None
    client_node: Node = None
    exp_type: str = None

    def __init__(self, configs):
        for key in configs:
            setattr(self, key, configs[key])

    def server_setup(self):
        for node in self.nodes:
            node.setup(self.storage_type)

    def start(self):
        for node in self.nodes:
            node.start()
        self.server_cleanup()

    def stop(self):
        self.server_cleanup()
        for node in self.nodes:
            node.stop()

    def initialize(self):
        pass

    def db_init(self):
        pass

    def get_leader(self):
        pass

    def get_follower(self):
        pass

    def benchmark_load(self):
        pass

    def benchmark_run(self):
        pass

    def db_cleanup(self):
        pass

    def server_cleanup(self):
        for node in self.nodes:
            node.cleanup()