#!/usr/bin/env xonsh

import os
import time
import psutil
import logging
from typing import List
from multiprocessing import Process

from structures.quorum import Quorum

children = []


def get_percent(process):
    return process.cpu_percent()


def get_memory(process):
    return process.memory_info()


def all_children(pr):
    global children

    try:
        children_of_pr = pr.children(recursive=True)
    except Exception:  # pragma: no cover
        return children

    for child in children_of_pr:
        if child not in children:
            children.append(child)

    return children


def monitor_usage(
    pid, logfile=None, plotfile=None, interval=None, include_children=True
):
    pr = psutil.Process(pid)

    start_time = time.time()

    if logfile:
        f = open(logfile, "w")
        f.write(
            "# {0:12s} {1:12s} {2:12s} {3:12s}\n".format(
                "Elapsed time".center(12),
                "CPU (%)".center(12),
                "Real (MB)".center(12),
                "Virtual (MB)".center(12),
            )
        )

    log = {"times": [], "cpu": [], "mem_real": [], "mem_virtual": []}

    try:
        while True:
            current_time = time.time()

            try:
                pr_status = pr.status()
            except TypeError:  # psutil < 2.0
                pr_status = pr.status
            except psutil.NoSuchProcess:  # pragma: no cover
                break

            if pr_status in [psutil.STATUS_ZOMBIE, psutil.STATUS_DEAD]:
                logging.info(
                    "Process finished ({0:.2f} seconds)".format(
                        current_time - start_time
                    )
                )
                break

            try:
                current_cpu = get_percent(pr)
                current_mem = get_memory(pr)
            except Exception:
                break
            current_mem_real = current_mem.rss / 1024.0**2
            current_mem_virtual = current_mem.vms / 1024.0**2

            if include_children:
                for child in all_children(pr):
                    try:
                        current_cpu += get_percent(child)
                        current_mem = get_memory(child)
                    except Exception:
                        continue
                    current_mem_real += current_mem.rss / 1024.0**2
                    current_mem_virtual += current_mem.vms / 1024.0**2

            if logfile:
                f.write(
                    "{0:12.3f} {1:12.3f} {2:12.3f} {3:12.3f}\n".format(
                        current_time - start_time,
                        current_cpu,
                        current_mem_real,
                        current_mem_virtual,
                    )
                )
                f.flush()

            if interval is not None:
                time.sleep(interval)

            if plotfile:
                log["times"].append(current_time - start_time)
                log["cpu"].append(current_cpu)
                log["mem_real"].append(current_mem_real)
                log["mem_virtual"].append(current_mem_virtual)

    except KeyboardInterrupt:
        pass

    if logfile:
        f.close()

    if plotfile:
        import matplotlib.pyplot as plt

        with plt.rc_context({"backend": "Agg"}):
            fig = plt.figure()
            ax = fig.add_subplot(1, 1, 1)

            ax.plot(log["times"], log["cpu"], "-", lw=1, color="r")

            ax.set_ylabel("CPU (%)", color="r")
            ax.set_xlabel("time (s)")
            ax.set_ylim(0.0, max(log["cpu"]) * 1.2)

            ax2 = ax.twinx()

            ax2.plot(log["times"], log["mem_real"], "-", lw=1, color="b")
            ax2.set_ylim(0.0, max(log["mem_real"]) * 1.2)

            ax2.set_ylabel("Real Memory (MB)", color="b")

            ax.grid()

            fig.savefig(plotfile)


def monitor_quorum(quorum, logfile=None, plotfile=None, interval=None):
    start_time = time.time()

    if logfile:
        f = open(logfile, "w")
        f.write(
            "# {0:12s} {1:12s}\n".format(
                "Elapsed time".center(12), "Leader Node".center(12)
            )
        )

    log = {"times": [], "leader": []}

    trail = 0
    max_trails = 15
    try:
        while True:
            current_time = time.time()
            
            try:
                leader_node = quorum.get_leader()
                trial = 0
            except Exception as e:
                logging.error(e)
                if trail < max_trails :
                    trail = trail + 1
                    sleep @(interval)
                    continue
                else:
                    break

            if logfile:
                f.write(
                    "{0:12.3f} {1:12s}\n".format(
                        current_time - start_time, leader_node.name
                    )
                )
                f.flush()

            if interval is not None:
                time.sleep(interval)

            if plotfile:
                log["times"].append(current_time - start_time)
                log["leader"].append(leader_node.name)

    except KeyboardInterrupt:
        pass

    if logfile:
        f.close()

    if plotfile:
        import matplotlib.pyplot as plt

        with plt.rc_context({"backend": "Agg"}):
            plt.figure()
            plt.plot(log["times"], log["leader"])
            plt.title("Leadership Changes VS Time")
            plt.xlabel("Time (s)")
            plt.ylabel("Leader Node")
            plt.savefig(plotfile)

def create_cgroups(node):
    #cpu cgroup
    node.run(f"sudo sh -c 'sudo mkdir /sys/fs/cgroup/cpu/{node.name}'", True)
    for pid in node.pids:
        node.run(f"sudo sh -c 'sudo echo {pid} > /sys/fs/cgroup/cpu/{node.name}/cgroup.procs'", True)

    #mem cgroup
    node.run(f"sudo sh -c 'sudo mkdir /sys/fs/cgroup/memory/{node.name}'", True)
    for pid in node.pids:
        node.run(f"sudo sh -c 'sudo echo {pid} > /sys/fs/cgroup/memory/{node.name}/cgroup.procs'", True)


def monitor(quorum: Quorum, output_path: str, interval: float):
    monitor_processes = []
    nodes = quorum.nodes
    for node in nodes:
        for pid in node.pids:
            logfile = os.path.join(output_path, f"{node.name}_{pid}.txt")
            plotfile = os.path.join(output_path, f"{node.name}_{pid}.png")
            proc = Process(
                target=monitor_usage,
                args=(pid,),
                kwargs={"logfile": logfile, "plotfile": plotfile, "interval": interval},
            )
            proc.start()
            monitor_processes.append(proc)

    logfile = os.path.join(output_path, "quorum_leadership.txt")
    plotfile = os.path.join(output_path, "quorum_leadership.png")
    proc = Process(
        target=monitor_quorum,
        args=(quorum,),
        kwargs={"logfile": logfile, "plotfile": plotfile, "interval": interval},
    )
    proc.start()
    monitor_processes.append(proc)

    return monitor_processes
