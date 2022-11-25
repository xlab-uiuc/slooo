#!/usr/bin/env xonsh

import logging

from structures.node import Node

def cpu_limit(node, slowness):
    '''
        cgroups is used to restrict cpu usage
        slowness is percentage of cpu usage
    '''
    period=1000000
    quota=int(float(slowness)*10000)
    node.run(f"sudo sh -c 'sudo echo {quota} > /sys/fs/cgroup/cpu/{node.hostname}/cpu.cfs_quota_us'", True)
    node.run(f"sudo sh -c 'sudo echo {period} > /sys/fs/cgroup/cpu/{node.hostname}/cpu.cfs_period_us'", True)


def cpu_contention(node, slowness):
    '''
        use stress-ng to simulate cpu contention
        slowness is the amount of cpu that should be hogged by stress-ng 
    '''

    node.run(f"sh -c 'nohup taskset -ac {node.cpu_affinity} stress-ng -c 0 -l {slowness} > /dev/null 2>&1 &'")


def disk_limit(node, slowness):
    '''
        use blkio to limit the read & write bps to a fixed value
        slowness should be given in bytes per second
    '''

    node.run("sudo sh -c 'sudo mkdir /sys/fs/cgroup/blkio/db'")
    node.run("sudo sh -c 'sync; echo 3 > /proc/sys/vm/drop_caches'")

    # get disk partition info
    dev_major_num = int(node.run(f"sudo sh -c 'stat {node.disk_partition} -c 0x%t"), 16)
    dev_minor_num = int(node.run(f"sudo sh -c 'stat {node.disk_partition} -c 0x%T"), 16)
    
    
    lsblkcmd=f"{dev_major_num}:{dev_minor_num} {slowness}"
    node.run(f"sudo sh -c 'sudo echo {lsblkcmd} > /sys/fs/cgroup/blkio/db/blkio.throttle.read_bps_device'")
    node.run(f"sudo sh -c 'sudo echo {lsblkcmd} > /sys/fs/cgroup/blkio/db/blkio.throttle.write_bps_device'")

    for pid in node.pids:
        node.run(f"sudo sh -c 'sudo echo {pid} > /sys/fs/cgroup/blkio/db/cgroup.procs'")


def disk_contention(node, slowness):
    '''
        run a program that does heavy write to the disk
        slowness is ignored
    '''

    clear_dd_file = os.path.join(os.path.dirname(os.path.realpath(__file__)), "clear_dd_file.sh")
    scp clear_dd_file @(node.ip):~/

    node.run(f"sh -c 'nohup taskset -ac {node.free_cpus} ./clear_dd_file.sh {slowness} {node.data_dir} > /dev/null 2>&1 &'")

def network_limit(node, slowness):
    node.run(f"sudo sh -c 'sudo /sbin/tc qdisc add dev eth0 root netem delay {slowness}ms'")

def memory_contention(node, slowness):
    '''
        use cgroups to limit the memory usage of the processes
        slowness is in bytes
    '''
    node.run(f"sudo sh -c 'sudo echo 1 > /sys/fs/cgroup/memory/{node.hostname}/memory.oom_control'", True)
    node.run(f"sudo sh -c 'sudo echo {slowness} > /sys/fs/cgroup/memory/{node.hostname}/memory.limit_in_bytes'", True)

def kill_process(node):
    for slow_pid in node.pids:
        node.run(f"sudo sh -c 'kill -9 {slow_pid}'")

func_map = {   
    "cpu_limit": cpu_limit,
    "cpu_contention": cpu_contention,
    "disk_limit": disk_limit,
    "disk_contention": disk_contention,
    "memory_contention": memory_contention,
    "network_limit": network_limit
}

def fault_inject(node, fault, slowness):
    logging.info(f"Injecting {fault} fault into {node}")
    if fault == "kill":
        kill_process(node)
    elif fault == "noslow":
        pass
    else:
        func_map[fault](node, slowness)
