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
    cpu = slow_server_config['cpu']
    scp resources/slowness/deadloop @(slow_ip):~/
    ssh -i ~/.ssh/id_rsa @(slow_ip) f"sh -c 'nohup taskset -ac {cpu} ./deadloop > /dev/null 2>&1 &'"
    deadlooppid=$(ssh -i ~/.ssh/id_rsa @(slow_ip) "sh -c 'pgrep deadloop'")
    ssh -i ~/.ssh/id_rsa @(slow_ip) "sudo sh -c 'sudo mkdir /sys/fs/cgroup/cpu/cpulow /sys/fs/cgroup/cpu/cpuhigh'"
    ssh -i ~/.ssh/id_rsa @(slow_ip) "sudo sh -c 'sudo echo 64 > /sys/fs/cgroup/cpu/cpulow/cpu.shares'"
    ssh -i ~/.ssh/id_rsa @(slow_ip) @("sudo sh -c 'sudo echo {} > /sys/fs/cgroup/cpu/cpuhigh/cgroup.procs'".format(deadlooppid))

    for slow_pid in slow_pids.split():
        ssh -i ~/.ssh/id_rsa @(slow_ip) @("sudo sh -c 'sudo echo {} > /sys/fs/cgroup/cpu/cpulow/cgroup.procs'".format(slow_pid))

#needs to be refactor
def disk_slow(node, slowness):
    ssh -i ~/.ssh/id_rsa @(slow_ip) "sudo sh -c 'sudo mkdir /sys/fs/cgroup/blkio/db'"
    ssh -i ~/.ssh/id_rsa @(slow_ip) "sudo sh -c 'sync; echo 3 > /proc/sys/vm/drop_caches'"
    lsblkcmd="8:32 524288"
    ssh -i ~/.ssh/id_rsa @(slow_ip) f"sudo sh -c 'sudo echo {lsblkcmd} > /sys/fs/cgroup/blkio/db/blkio.throttle.read_bps_device'"
    ssh -i ~/.ssh/id_rsa @(slow_ip) f"sudo sh -c 'sudo echo {lsblkcmd} > /sys/fs/cgroup/blkio/db/blkio.throttle.write_bps_device'"
    for slow_pid in slow_pids.split():
        ssh -i ~/.ssh/id_rsa @(slow_ip) @("sudo sh -c 'sudo echo {} > /sys/fs/cgroup/blkio/db/cgroup.procs'".format(slow_pid))

#needs to be refactored
def disk_contention(node, slowness):
    ssh -i ~/.ssh/id_rsa @(slow_ip) "sh -c 'nohup taskset -ac 2 ./clear_dd_file.sh > /dev/null 2>&1 &'"

def network_slow(node, slowness):
    node.run("sudo sh -c 'sudo /sbin/tc qdisc add dev eth0 root netem delay {int(slowness)}ms')

def memory_contention(node, slowness):
    node.run("sudo sh -c 'sudo mkdir /sys/fs/cgroup/memory/db'")
    node.run("sudo sh -c 'sudo echo 1 > /sys/fs/cgroup/memory/db/memory.oom_control'")
    node.run("sudo sh -c 'sudo echo {slowness} > /sys/fs/cgroup/memory/db/memory.limit_in_bytes'")

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
