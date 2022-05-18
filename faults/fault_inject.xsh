#!/usr/bin/env xonsh

from utils.node import Node

def cpu_slow(node, slowness):
    period=1000000
    quota=float(slowness)*10000
    node.run("sudo sh -c 'sudo mkdir /sys/fs/cgroup/cpu/db'")
    node.run(f"sudo sh -c 'sudo echo {quota} > /sys/fs/cgroup/cpu/db/cpu.cfs_quota_us'")
    node.run(f"sudo sh -c 'sudo echo {period} > /sys/fs/cgroup/cpu/db/cpu.cfs_period_us'")
    for slow_pid in node.pids:
        node.run(f"sudo sh -c 'sudo echo {slow_pid} > /sys/fs/cgroup/cpu/db/cgroup.procs'")

#needs to be refactored
def cpu_contention(node, slowness):
    '''
        use cgroup to specify the maximum cpu share for the process
        slowness should be given in a decimal that describes the percentage of cpu to be used by tge program 
    '''
    program_cpu_share = int(float(slowness) * 1024)

    # TODO: modify the path of deadloop
    scp resources/slowness/deadloop @(node.ip):~/

    node.run(f"sh -c 'nohup taskset -ac {node.cpu_affinity} ./deadloop > /dev/null 2>&1 &'")
    deadloop_pid=node.run("sh -c 'pgrep deadloop'")
    node.run("sudo sh -c 'sudo mkdir /sys/fs/cgroup/cpu/cpulow /sys/fs/cgroup/cpu/cpuhigh'")
    node.run(f"sudo cgset -r cpu.shares={1024-program_cpu_share} cpuhigh")
    node.run(f"sudo cgset -r cpu.shares={program_cpu_share} cpulow")
    node.run(f"sudo sh -c 'sudo echo {deadloop_pid} > /sys/fs/cgroup/cpu/cpuhigh/cgroup.procs'")
    for pid in node.pids:
        node.run(f"sudo sh -c 'sudo echo {pid} > /sys/fs/cgroup/cpu/cpulow/cgroup.procs'")

#needs to be refactored
def disk_slow(node, slowness):
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

#needs to be refactored

def disk_contention(node, slowness):
    '''
        run a program that does heavy write to the disk
        slowness is ignored
    '''
    # TODO: this clear_dd_file script may not run correctly due to not-exist directory
    node.run("sh -c 'nohup taskset -ac 2 ./clear_dd_file.sh > /dev/null 2>&1 &'")

def network_slow(node, slowness):
    node.run(f"sudo sh -c 'sudo /sbin/tc qdisc add dev eth0 root netem delay {int(slowness)}ms'")

def memory_contention(node, slowness):
    node.run("sudo sh -c 'sudo mkdir /sys/fs/cgroup/memory/db'")
    node.run("sudo sh -c 'sudo echo 1 > /sys/fs/cgroup/memory/db/memory.oom_control'")
    node.run(f"sudo sh -c 'sudo echo {slowness} > /sys/fs/cgroup/memory/db/memory.limit_in_bytes'")

    for slow_pid in node.pids:
        node.run(f"sudo sh -c 'sudo echo {slow_pid} > /sys/fs/cgroup/memory/db/cgroup.procs'")

def kill_process(node, slowness):
    for slow_pid in node.pids:
        node.run(f"sudo sh -c 'kill -9 {pid}'")

slow_vs_num = {1: cpu_slow,
               2: cpu_contention,
               3: disk_slow,
               4: disk_contention,
               5: memory_contention,
               6: network_slow}

def fault_inject(node, exp, slowness):
    if exp == "kill":
        kill_process(node)
    elif exp == "noslow":
        pass
    else:
        slow_vs_num[int(exp)](node, slowness)
    
    sleep 30
