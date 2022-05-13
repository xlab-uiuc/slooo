#!/usr/bin/env xonsh

from typing import List

class Node:
    name: str = None
    ip: str = None
    cpu_affinity: str = None
    pids: List[int] = None
    resource_group = None
    subscription = None

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

    def __init__(self, configs, **kwargs):
        for key, value in configs.items():
            setattr(self, key, value)

        for key, value in kwargs.items():
            setattr(self, key, value)

    def __str__(self):
        return "Node: {json.dumps(self.to_json())}"

    def to_json(self):
        return {
            "name": self.name,
            "ip": self.ip
        }

    def run(self, command):
        ssh -i ~/.ssh/id_rsa @(self.ip) @(command)

    def update(self, configs):
        for key, value in configs.items():
            setattr(self, key, value)

    def kill_process(self):
        pass

    def stop(self):
        if self.ip == "localhost":
            return
        az vm deallocate --resource-group @(self.resource_group) --subscription @(self.subscription) --name @(self.name)

    def start(self):
        if self.ip == "localhost":
            return
        az vm start --resource-group @(self.resource_group) --subscription @(self.subscription) --name @(self.name)

    def setup(self, storage_type):
        if storage_type == "disk":
            cmd = f"sudo sh -c 'sudo umount {self.disk_partition} ;\
                                sudo mkdir -p {self.data_dir} ;\
                                sudo mkfs.{self.file_system} {self.disk_partition} -f ;\
                                sudo mount -t {self.file_system} {self.disk_partition} {self.data_dir} ;\
                                sudo mount -t xfs {self.disk_partition} {self.data_dir} -o remount,noatime ;\
                                sudo chmod o+w {self.data_dir}'"

            self.run(cmd)
        elif storage_type == "mem":
            cmd = f"sudo sh -c 'sudo mkdir -p {self.data_dir} ;\
                                sudo mount -t tmpfs -o rw,size={self.ramdisk_size} tmpfs {self.data_dir} ;\
                                sudo chmod o+w {self.data_dir}'"
            self.run(cmd)

    def cleanup(self):
        cmd = f"sudo sh -c 'sudo rm -rf {self.data_dir} ;\
                            sudo umount -f -l {self.disk_partition} ;\
                            sudo cgdelete cpu:db cpu:cpulow cpu:cpuhigh blkio:db ; true ;\
                            sudo /sbin/tc qdisc del dev eth0 root ; true ;\
                            pkill {self.process}'"

        self.run(cmd)