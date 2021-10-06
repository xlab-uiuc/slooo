#!/usr/bin/env xonsh
from mongo.temp import *
from polardb.temp import *

def parse_opt():
    parser = argparse.ArgumentParser()
    parser.add_argument("--system", type=str, help="mongodb/rethinkdb/tidb/polardb")
    parser.add_argument("--iters", type=int, default=1, help="number of iterations")
    parser.add_argument("--workload", type=str, default="resources/workloads/workloada", help="workload path")
    parser.add_argument("--server-configs", type=str, default="server_configs.json", help="server config path")
    parser.add_argument("--runtime", type=int, default=300, help="runtime")
    parser.add_argument("--exps", type=str, default="noslow", help="experiments to be ran saperated by commas(,)")
    parser.add_argument("--exp-type", type=str, default="follower", help="leader/follower/learner(only for polardb)")
    parser.add_argument("--ondisk", type=str, default="disk", help="in memory(mem) or on disk (disk)")
    parser.add_argument("--threads", type=int, default=250, help="no. of logical clients")
    parser.add_argument("--output-path", type=str, default="results", help="results output path")
    parser.add_argument("--cleanup", action='store_true', help="clean's up the servers")
    opt = parser.parse_args()
    return opt

def main(opt):
    if opt.cleanup:
        if opt.system == "mongodb":
            DB = MongoDB(opt=opt)
        elif opt.system == "rethinkdb":
            DB = RethinkDB(opt=opt)
        elif opt.system == "tidb":
            DB = TiDB(opt=opt)
        elif opt.system == "polardb":
            DB = PolarDB(opt=opt)
        DB.cleanup()
        return

    DB = PolarDB(opt=opt, trial=1, exp="noslow")
    DB.start_db()
    DB.db_init()
    DB.pgbench_load()
    # TODO adapt to local mode please
    DB.get_pidslist()
    DB.set_affinity()
        
        
    DB.pgbench_run()
        
    DB.polar_cleanup()

    print("pidslist\n",DB.pidslist)
    print("ppidlist",DB.ppidlist)

if __name__ == "__main__":
    opt = parse_opt()
    main(opt)
