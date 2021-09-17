#!/usr/bin/env xonsh
import json

global slow_config

def cpu_slow(host_id, secondaryip, secondarypids):
    percentage = slow_config["cpu_slow_percentage"]

    period=1000000
    # calculate quota with accord to the percentage specified
    quota=int(period * percentage)

    ssh -i ~/.ssh/id_rsa @(host_id)@@(secondaryip) "sudo sh -c 'sudo mkdir /sys/fs/cgroup/cpu/db'"
    ssh -i ~/.ssh/id_rsa @(host_id)@@(secondaryip) @("sudo sh -c 'sudo echo {} > /sys/fs/cgroup/cpu/db/cpu.cfs_quota_us'".format(quota))
    ssh -i ~/.ssh/id_rsa @(host_id)@@(secondaryip) @("sudo sh -c 'sudo echo {} > /sys/fs/cgroup/cpu/db/cpu.cfs_period_us'".format(period))
    
    for secondarypid in secondarypids.split():
        ssh -i ~/.ssh/id_rsa @(host_id)@@(secondaryip) @("sudo sh -c 'sudo echo {} > /sys/fs/cgroup/cpu/db/cgroup.procs'".format(secondarypid))

def cpu_contention(host_id, secondaryip, secondarypids):
    ratio = slow_config["cpu_contention_ratio"]

    scp resources/slowness/deadloop @(host_id)@@(secondaryip):~/
    ssh -i ~/.ssh/id_rsa @(host_id)@@(secondaryip) "sh -c 'nohup taskset -ac 0 ./deadloop > /dev/null 2>&1 &'"
    deadlooppid=$(ssh -i ~/.ssh/id_rsa @(host_id)@@(secondaryip) "sh -c 'pgrep deadloop'")
    ssh -i ~/.ssh/id_rsa @(host_id)@@(secondaryip) "sudo sh -c 'sudo mkdir /sys/fs/cgroup/cpu/cpulow /sys/fs/cgroup/cpu/cpuhigh'"
    ssh -i ~/.ssh/id_rsa @(host_id)@@(secondaryip) @("sudo sh -c 'sudo echo {} > /sys/fs/cgroup/cpu/cpulow/cpu.shares'".format(int(1024 / ratio))) #BUG what if int(1024 / ratio) evaluates to 0?
    ssh -i ~/.ssh/id_rsa @(host_id)@@(secondaryip) @("sudo sh -c 'sudo echo {} > /sys/fs/cgroup/cpu/cpuhigh/cgroup.procs'".format(deadlooppid))

    for secondarypid in secondarypids.split():
        ssh -i ~/.ssh/id_rsa @(host_id)@@(secondaryip) @("sudo sh -c 'sudo echo {} > /sys/fs/cgroup/cpu/cpulow/cgroup.procs'".format(secondarypid))

def disk_slow(host_id, secondaryip, secondarypids):
    bps = slow_config["disk_slow_bps"]

    ssh -i ~/.ssh/id_rsa @(host_id)@@(secondaryip) "sudo sh -c 'sudo mkdir /sys/fs/cgroup/blkio/db'"
    ssh -i ~/.ssh/id_rsa @(host_id)@@(secondaryip) "sudo sh -c 'sync; echo 3 > /proc/sys/vm/drop_caches'"
    lsblkcmd=@("8:32 {}".format(bps))
    ssh -i ~/.ssh/id_rsa @(host_id)@@(secondaryip) "sudo sh -c 'sudo echo $lsblkcmd > /sys/fs/cgroup/blkio/db/blkio.throttle.read_bps_device'"                 
    ssh -i ~/.ssh/id_rsa @(host_id)@@(secondaryip) "sudo sh -c 'sudo echo $lsblkcmd > /sys/fs/cgroup/blkio/db/blkio.throttle.write_bps_device'"                                                                                                                         
    for secondarypid in secondarypids.split():
        ssh -i ~/.ssh/id_rsa @(host_id)@@(secondaryip) @("sudo sh -c 'sudo echo {} > /sys/fs/cgroup/blkio/db/cgroup.procs'".format(secondarypid))

def disk_contention(host_id, secondaryip, secondarypids):
    ssh -i ~/.ssh/id_rsa @(host_id)@@(secondaryip) "sh -c 'nohup taskset -ac 2 ./clear_dd_file.sh > /dev/null 2>&1 &'"

def network_slow(host_id, secondaryip, secondarypids):
    latency = slow_config["network_slow_latency"]
    
    ssh -i ~/.ssh/id_rsa @(host_id)@@(secondaryip) @("sudo sh -c 'sudo /sbin/tc qdisc add dev eth0 root netem delay {}ms'".format(latency))

def memory_contention(host_id, secondaryip, secondarypids):
    set -ex
    
    mem_limit_in_bytes = slow_config["memory_contention_mem_limit_in_bytes"]
    
    ssh -i ~/.ssh/id_rsa @(host_id)@@(secondaryip) "sudo sh -c 'sudo mkdir /sys/fs/cgroup/memory/db'"
    #ssh -i ~/.ssh/id_rsa "$host_id"@"$secondaryip" "sudo sh -c 'sudo echo 1 > /sys/fs/cgroup/memory/db/memory.memsw.oom_control'"  # disable OOM killer
    #ssh -i ~/.ssh/id_rsa "$host_id"@"$secondaryip" "sudo sh -c 'sudo echo 10485760 > /sys/fs/cgroup/memory/db/memory.memsw.limit_in_bytes'"   # 10MB
    # ssh -i ~/.ssh/id_rsa "$host_id"@"$secondaryip" "sudo sh -c 'sudo echo 1 > /sys/fs/cgroup/memory/db/memory.oom_control'"  # disable OOM killer
    ssh -i ~/.ssh/id_rsa @(host_id)@@(secondaryip) @("sudo sh -c 'sudo echo {} > /sys/fs/cgroup/memory/db/memory.limit_in_bytes'".format(mem_limit_in_bytes))   # 5MB
    
    for secondarypid in secondarypids.split():
        ssh -i ~/.ssh/id_rsa @(host_id)@@(secondaryip) @("sudo sh -c 'sudo echo {} > /sys/fs/cgroup/memory/db/cgroup.procs'".format(secondarypid))

slow_vs_num = {1: cpu_slow,
               2: cpu_contention,
               3: disk_slow,
               4: disk_contention,
               5: memory_contention,
               6: network_slow}

def slow_inject(exp, host_id, secondaryip, secondarypids, slow_config_path):
    with open(slow_config_path, 'r') as input:
        slow_config_json = input.read()
	slow_config = json.loads(slow_config_json)
    # TODO: check validity of the slow config | not a issue if users always use the slow_config_gen script to generate slow_files
    # LOGGING: print the slowness injected and the slowness config (or path to the config file)
    slow_vs_num[int(exp)](host_id, secondaryip, secondarypids)
    sleep 30

