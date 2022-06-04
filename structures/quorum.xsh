#!/usr/bin/env xonsh

from typing import List

from structures.node import Node
from utils.common_utils import *

class Quorum:
    nodes: List[Node] = None
    client_configs = None

    def __init__(self, *args, **kwargs):
        for key in kwargs:
            setattr(self, key, kwargs[key])

    def start(self):
        for node in self.nodes:
            node.start()
        self.server_cleanup()

    def stop(self):
        self.server_cleanup()
        for node in self.nodes:
            node.stop()

    def server_setup(self, storage_type):
        for node in self.nodes:
            node.setup(storage_type)

    def initialize(self):
        pass

    def db_init(self):
        pass

    def set_node_pids(self):
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

    def setup(self, storage_type="disk"):
        self.start()
        self.server_setup(storage_type)
        self.initialize()
        self.db_init()
        self.set_node_pids()

    def teardown():
        self.db_cleanup()
        self.server_cleanup()