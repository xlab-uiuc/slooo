from typing import List

class Node:
    name: str = None
    ip: str = None
    cpu_affinity: str = None
    pids: List[int] = None

    #server
    data_dir: str = None
    disk_partition: str = None
    file_system: str = None
    swapfile: str = None
    swapbs: int = None
    swapcount: int = None
    ramdisk_size: str = None
    port_offset: int = None
    quorum_process: str = None

    #client
    workload: str = None
    num_clients: int = None
    runtime: int = None
    output: str = None
    benchmark_bin: str = None

    def __init__(self, configs):
        for key in configs:
            setattr(self, key, args[key])

    def run_command(self, command):
        ssh -i ~/.ssh/id_rsa @(self.ip) @(command)

    def update(self, configs):
        for key in configs:
            setattr(self, key, args[key])

    def kill_process(self):
        pass