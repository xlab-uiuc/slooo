#!/usr/bin/env xonsh

import os
import json
import psutil

def get_cpids(pid: int):
    cpids = $(pgrep -P @(pid)).split()
    cpids = [int(x) for x in cpids]
    res = cpids
    for cpid in cpids:
        res.extend(get_cpids(cpid))

    return res

def pid_status(pid):
    pr = psutil.Process(pid)
    try:
        pr_status = pr.status()
    except TypeError:  # psutil < 2.0
        pr_status = pr.status
    except psutil.NoSuchProcess:  # pragma: no cover
        pr_status = -1

    return pr_status not in [psutil.STATUS_ZOMBIE, psutil.STATUS_DEAD]