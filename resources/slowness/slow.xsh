#!/usr/bin/env xonsh


def cpu_slow(secondary_server_config, secondaryip, secondarypids):
    quota=50000
    period=1000000
    ssh -i ~/.ssh/id_rsa @(host_id)@@(secondaryip) "sudo sh -c 'sudo mkdir /sys/fs/cgroup/cpu/db'"
    ssh -i ~/.ssh/id_rsa @(host_id)@@(secondaryip) @("sudo sh -c 'sudo echo {} > /sys/fs/cgroup/cpu/db/cpu.cfs_quota_us'".format(quota))
    ssh -i ~/.ssh/id_rsa @(host_id)@@(secondaryip) @("sudo sh -c 'sudo echo {} > /sys/fs/cgroup/cpu/db/cpu.cfs_period_us'".format(period))
    
    for secondarypid in secondarypids.split():
        ssh -i ~/.ssh/id_rsa @(host_id)@@(secondaryip) @("sudo sh -c 'sudo echo {} > /sys/fs/cgroup/cpu/db/cgroup.procs'".format(secondarypid))

def cpu_contention(secondary_server_config, secondaryip, secondarypids):
    cpu = secondary_server_config['cpu']
    scp resources/slowness/deadloop @(host_id)@@(secondaryip):~/
    ssh -i ~/.ssh/id_rsa @(host_id)@@(secondaryip) "sh -c 'nohup taskset -ac {cpu} ./deadloop > /dev/null 2>&1 &'"
    deadlooppid=$(ssh -i ~/.ssh/id_rsa @(host_id)@@(secondaryip) "sh -c 'pgrep deadloop'")
    ssh -i ~/.ssh/id_rsa @(host_id)@@(secondaryip) "sudo sh -c 'sudo mkdir /sys/fs/cgroup/cpu/cpulow /sys/fs/cgroup/cpu/cpuhigh'"
    ssh -i ~/.ssh/id_rsa @(host_id)@@(secondaryip) "sudo sh -c 'sudo echo 64 > /sys/fs/cgroup/cpu/cpulow/cpu.shares'"
    ssh -i ~/.ssh/id_rsa @(host_id)@@(secondaryip) @("sudo sh -c 'sudo echo {} > /sys/fs/cgroup/cpu/cpuhigh/cgroup.procs'".format(deadlooppid))

    for secondarypid in secondarypids.split():
        ssh -i ~/.ssh/id_rsa @(host_id)@@(secondaryip) @("sudo sh -c 'sudo echo {} > /sys/fs/cgroup/cpu/cpulow/cgroup.procs'".format(secondarypid))

def disk_slow(secondary_server_config, secondaryip, secondarypids):
    ssh -i ~/.ssh/id_rsa @(host_id)@@(secondaryip) "sudo sh -c 'sudo mkdir /sys/fs/cgroup/blkio/db'"
    ssh -i ~/.ssh/id_rsa @(host_id)@@(secondaryip) "sudo sh -c 'sync; echo 3 > /proc/sys/vm/drop_caches'"
    lsblkcmd="8:32 524288"
    ssh -i ~/.ssh/id_rsa @(host_id)@@(secondaryip) "sudo sh -c 'sudo echo $lsblkcmd > /sys/fs/cgroup/blkio/db/blkio.throttle.read_bps_device'"                 
    ssh -i ~/.ssh/id_rsa @(host_id)@@(secondaryip) "sudo sh -c 'sudo echo $lsblkcmd > /sys/fs/cgroup/blkio/db/blkio.throttle.write_bps_device'"                                                                                                                         
    for secondarypid in secondarypids.split():
        ssh -i ~/.ssh/id_rsa @(host_id)@@(secondaryip) @("sudo sh -c 'sudo echo {} > /sys/fs/cgroup/blkio/db/cgroup.procs'".format(secondarypid))

def disk_contention(secondary_server_config, secondaryip, secondarypids):
    ssh -i ~/.ssh/id_rsa @(host_id)@@(secondaryip) "sh -c 'nohup taskset -ac 2 ./clear_dd_file.sh > /dev/null 2>&1 &'"

def network_slow(secondary_server_config, secondaryip, secondarypids):
    ssh -i ~/.ssh/id_rsa @(host_id)@@(secondaryip) "sudo sh -c 'sudo /sbin/tc qdisc add dev eth0 root netem delay 400ms'"

def memory_contention(secondary_server_config, secondaryip, secondarypids):
    set -ex

    ssh -i ~/.ssh/id_rsa @(host_id)@@(secondaryip) "sudo sh -c 'sudo mkdir /sys/fs/cgroup/memory/db'"
    #ssh -i ~/.ssh/id_rsa "$host_id"@"$secondaryip" "sudo sh -c 'sudo echo 1 > /sys/fs/cgroup/memory/db/memory.memsw.oom_control'"  # disable OOM killer
    #ssh -i ~/.ssh/id_rsa "$host_id"@"$secondaryip" "sudo sh -c 'sudo echo 10485760 > /sys/fs/cgroup/memory/db/memory.memsw.limit_in_bytes'"   # 10MB
    # ssh -i ~/.ssh/id_rsa "$host_id"@"$secondaryip" "sudo sh -c 'sudo echo 1 > /sys/fs/cgroup/memory/db/memory.oom_control'"  # disable OOM killer
    ssh -i ~/.ssh/id_rsa @(host_id)@@(secondaryip) "sudo sh -c 'sudo echo 47088768 > /sys/fs/cgroup/memory/db/memory.limit_in_bytes'"   # 5MB
    
    for secondarypid in secondarypids.split():
        ssh -i ~/.ssh/id_rsa @(host_id)@@(secondaryip) @("sudo sh -c 'sudo echo {} > /sys/fs/cgroup/memory/db/cgroup.procs'".format(secondarypid))

slow_vs_num = {1: cpu_slow,
               2: cpu_contention,
               3: disk_slow,
               4: disk_contention,
               5: memory_contention,
               6: network_slow}

def slow_inject(exp, secondary_server_config, secondaryip, secondarypids):
    slow_vs_num[int(exp)](secondary_server_config, secondaryip, secondarypids)
    sleep 30

# this function tests if the pids are properly added to cgroup.procs
def slow_inject_verify(pids):
    print("Original pid list\n", pids)
    sudo mkdir /sys/fs/cgroup/cpu/test
    for pid in pids.split():
        print(pid)
        sudo sh -c @("sudo echo {} > /sys/fs/cgroup/cpu/test/cgroup.procs".format(pid))
    print("Now in procs")
    cat /sys/fs/cgroup/cpu/test/cgroup.procs
    print("\nDeleting the test cgroup")
    sudo cgdelete cpu:test
