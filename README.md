# slooo: A Fail-slow Fault Injection Testing Infra

The goal of this project is to build a generic, reusable testing infrastructure that can be effectively used for any distributed systems (we can start from Raft or other consensus systems), rather than a bunch of ad hoc scripts.

IMPORTANT:  
Only works with Microsoft Azure (so far).

TODO:

**REVIST ALL THE COMMENTS WITH **revist** BEFORE THE DEADLINE**
**LOGGING**

Command:
```
usage: xonsh run.xsh [-h] [--system SYSTEM] [--iters ITERS] [--workload WORKLOAD] 
[--server-configs SERVER_CONFIGS] [--runtime RUNTIME] [--exps EXPS] [--exp-type EXP_TYPE] 
[--swap] [--ondisk ONDISK] [--threads THREADS] [--diagnose] [--output-path OUTPUT_PATH] [--cleanup]

optional arguments:
  -h, --help            help
  --system SYSTEM       mongodb / rethinkdb
  --iters ITERS         number of iterations
  --workload WORKLOAD   workload path
  --server-configs SERVER_CONFIGS
                        server config path
  --runtime RUNTIME     runtime
  --exps EXPS           experiments to be ran saperated by commas(,)
  --exp-type EXP_TYPE   leader / follower
  --swap                Swapniess on
  --ondisk ONDISK       in memory (mem) or on disk (disk)
  --threads THREADS     no. of logical clients
  --diagnose            collect diagnostic data (only for mongodb)
  --output-path OUTPUT_PATH
                        results output path
  --cleanup             clean's up the servers
  ```
