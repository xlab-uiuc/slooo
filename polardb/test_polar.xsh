#!/usr/bin/env xonsh

from polardb.temp import *


parser = argparse.ArgumentParser()
parser.add_argument("--iters", type=int, default=2, help="number of iterations")
parser.add_argument("--pgbench_scalefactor", type=int, default=32, help="scale factor of pgbench workload (value <= 32)")
parser.add_argument("--server-configs", type=str, default="server_configs.json", help="server config path")
parser.add_argument("--runtime", type=int, default=30, help="runtime")
parser.add_argument("--exps", type=str, default="noslow", help="experiments to be ran saperated by commas(,)")
parser.add_argument("--exp-type", type=str, default="follower", help="leader/follower/learner(only for PolarDB)")
parser.add_argument("--threads", type=int, default=16, help="no. of logical clients")
parser.add_argument("--output-path", type=str, default="results", help="results output path")
opt = parser.parse_args()
print(opt)
print(type(opt))
#params = {}
#params["iters"] = 2
#params["pgbench_scalefactor"] = 32
#params["server-configs"] = "server_configs.json"
#params["runtime"] = 30
#params["exps"] = "noslow" # Skip slowness injection for now
#params["exp-type"] = "follower" # TODO verify if the ips is correct
#params["threads"] = 16
#params["output-path"] = "slooo_polar_results"

DB = PolarDB(opt=opt, trial=1, exp=None)

DB.run()
