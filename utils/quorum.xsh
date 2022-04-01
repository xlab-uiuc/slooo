from typing import List

from utils.node import Node
from utils.common_utils import *

class Quorum:
    storage: str = "disk"
    server_nodes: List[Nodes] = None
    client_node: Node = None
    exp_type: str = None

    def __init__(self, configs):
        for key in configs:
            setattr(self, key, args[key])

    def server_setup(self):
        if self.storage == "disk":
            for node in self.nodes:
                init_disk(node)
        elif self.storage == "mem":
            for node in self.nodes:
                inti_memory(node)
        set_swap_config(self.server_configs, self.swap)

    def start_quorum(self):
        pass

    def init_quorum(self):
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
        pass