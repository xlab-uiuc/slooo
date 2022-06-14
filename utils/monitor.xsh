#!/usr/bin/env xonsh

import os
import time
import psutil
import logging
from typing import List
from multiprocessing import Process

from structures.node import Node
from structures.quorum import Quorum


def get_cpu_ss(node):
    ss = node.run(f"cat /sys//fs/cgroup/cpu/{node.name}/cpuacct.usage ; date +%s%N")
    return [int(x) for x in ss.split()]

def get_memory(node):
    ss = node.run(f"cat /sys//fs/cgroup/memory/{node.name}/memory.usage_in_bytes")
    return int(ss.strip())

def monitor_usage(
    node: Node, logfile=None, plotfile=None, interval=None, include_children=True
):
    start_time = time.time()

    if logfile:
        f = open(logfile, "w")
        f.write(
            "# {0:12s} {1:12s} {2:12s}\n".format(
                "Elapsed time".center(12),
                "CPU (%)".center(12),
                "Memory Usage (MB)".center(12),
            )
        )

    log = {"times": [], "cpu": [], "mem": []}

    prev_cpu_ss = None
    prev_node_time = None

    try:
        while True:
            current_time = time.time()

            try:
                curr_cpu_ss, curr_node_time = get_cpu_ss(node)
                current_mem = get_memory(node) / 1024**2
            except Exception:
                break

            if prev_cpu_ss:
                current_cpu = ((curr_cpu_ss - prev_cpu_ss) * 100) / (curr_node_time - prev_node_time)
            else:
                prev_cpu_ss = curr_cpu_ss
                prev_node_time = curr_node_time
                continue

            prev_cpu_ss = curr_cpu_ss
            prev_node_time = curr_node_time

            if logfile:
                f.write(
                    "{0:12.3f} {1:12.3f} {2:12.3f}\n".format(
                        current_time - start_time,
                        current_cpu,
                        current_mem,
                    )
                )
                f.flush()

            if interval is not None:
                time.sleep(interval)

            if plotfile:
                log["times"].append(current_time - start_time)
                log["cpu"].append(current_cpu)
                log["mem"].append(current_mem)

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

            ax2.plot(log["times"], log["mem"], "-", lw=1, color="b")
            ax2.set_ylim(0.0, max(log["mem"]) * 1.2)

            ax2.set_ylabel("Memory Usage (MB)", color="b")

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



def monitor(quorum: Quorum, output_path: str, interval: float):
    monitor_processes = []
    nodes = quorum.nodes
    for node in nodes:
        logfile = os.path.join(output_path, f"{node.name}.txt")
        plotfile = os.path.join(output_path, f"{node.name}.png")
        proc = Process(
            target=monitor_usage,
            args=(node,),
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