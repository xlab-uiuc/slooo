#!/usr/bin/env xonsh
__xonsh__.commands_cache.threadable_predictors['ssh'] = lambda *a, **kw: True

import json
import logging

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
    port: int = None
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
        return f"Node: {json.dumps(self.to_json())}"

    def to_json(self):
        return {
            "name": self.name,
            "ip": self.ip,
            "pids": self.pids
        }

    def run(self, command, raise_error=False):
        # ssh -i ~/.ssh/id_rsa @(self.ip) @(command)
        response = !(ssh -i ~/.ssh/id_rsa @(self.ip) @(command))
        if response.returncode == 0:
            return response.output
        else:
            if raise_error:
                raise Exception(response.errors)
            else:
                logging.warning(response.errors)

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
                                sudo mount -t {self.file_system} {self.disk_partition} {self.data_dir} -o remount,noatime ;\
                                sudo chmod o+w {self.data_dir}'"

            self.run(cmd)
        elif storage_type == "mem":
            cmd = f"sudo sh -c 'sudo mkdir -p {self.data_dir} ;\
                                sudo mount -t tmpfs -o rw,size={self.ramdisk_size} tmpfs {self.data_dir} ;\
                                sudo chmod o+w {self.data_dir}'"
            self.run(cmd)

    def cleanup(self):
        cmd = f"sudo sh -c 'sudo umount -f {self.data_dir} ;\
                            sudo rm -rf {self.data_dir} ;\
                            sudo cgdelete cpu:db cpu:cpulow cpu:cpuhigh blkio:db memory:db ; true ;\
                            sudo /sbin/tc qdisc del dev eth0 root ; true ;\
                            pkill {self.quorum_process}'"

        self.run(cmd)