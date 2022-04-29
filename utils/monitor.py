# Copyright (c) 2013, Thomas P. Robitaille
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice,
# this list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

# repo: https://github.com/astrofrog/psrecord

from __future__ import (unicode_literals, division, print_function,
                        absolute_import)

import time
import psutil

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


def monitor(pid, logfile=None, plotfile=None, interval=None,
            include_children=True):
    pr = psutil.Process(pid)

    start_time = time.time()

    if logfile:
        f = open(logfile, 'w')
        f.write("# {0:12s} {1:12s} {2:12s} {3:12s}\n".format(
            'Elapsed time'.center(12),
            'CPU (%)'.center(12),
            'Real (MB)'.center(12),
            'Virtual (MB)'.center(12))
        )

    log = {'times': [], 'cpu': [], 'mem_real': [], 'mem_virtual': []}

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
                print("Process finished ({0:.2f} seconds)"
                      .format(current_time - start_time))
                break

            try:
                current_cpu = get_percent(pr)
                current_mem = get_memory(pr)
            except Exception:
                break
            current_mem_real = current_mem.rss / 1024. ** 2
            current_mem_virtual = current_mem.vms / 1024. ** 2

            if include_children:
                for child in all_children(pr):
                    try:
                        current_cpu += get_percent(child)
                        current_mem = get_memory(child)
                    except Exception:
                        continue
                    current_mem_real += current_mem.rss / 1024. ** 2
                    current_mem_virtual += current_mem.vms / 1024. ** 2

            if logfile:
                f.write("{0:12.3f} {1:12.3f} {2:12.3f} {3:12.3f}\n".format(
                    current_time - start_time,
                    current_cpu,
                    current_mem_real,
                    current_mem_virtual))
                f.flush()

            if interval is not None:
                time.sleep(interval)

            if plotfile:
                log['times'].append(current_time - start_time)
                log['cpu'].append(current_cpu)
                log['mem_real'].append(current_mem_real)
                log['mem_virtual'].append(current_mem_virtual)

    except KeyboardInterrupt:
        pass

    if logfile:
        f.close()

    if plotfile:
        import matplotfilelib.pyplotfile as plt
        with plt.rc_context({'backend': 'Agg'}):
            fig = plt.figure()
            ax = fig.add_subplotfile(1, 1, 1)

            ax.plotfile(log['times'], log['cpu'], '-', lw=1, color='r')

            ax.set_ylabel('CPU (%)', color='r')
            ax.set_xlabel('time (s)')
            ax.set_ylim(0., max(log['cpu']) * 1.2)

            ax2 = ax.twinx()

            ax2.plotfile(log['times'], log['mem_real'], '-', lw=1, color='b')
            ax2.set_ylim(0., max(log['mem_real']) * 1.2)

            ax2.set_ylabel('Real Memory (MB)', color='b')

            ax.grid()

            fig.savefig(plotfile)