# A Tutorial of Using Slooo to Run a Fault-Injection Testing on MongoDB

`Slooo` helps the user to run fail-slow and fail-stop fault tolerance experiments without putting a lot of effort into writing a lot of scripts, we believe that there is a lot of reusable code that can be used if structured in a proper way and that is what this project is about. 

`Slooo` is written using [Xonsh](https://xon.sh/). Xonsh is a Python-powered, cross-platform, Unix-gazing shell language and commands prompt. We suggest having a brief look at Xonsh [documentation](https://xon.sh/contents.html) before getting started with porting a new system into Slooo.

The basic steps in the fail-slow and fail-stop fault tolerance tests are:
1. Environment setup for the system
2. Starting the system
3. Injecting a fault (Slow or Stop)
4. Benchmarking the System
5. Analyzing the results from different injected faults

In Slooo all the server configs are to be added to a server_configs.json and given as an input while running Slooo. All 
the server configs like disk partition, ip address, file system etc., are taken from this json file.
A standard server configs json file required by the RSM class can be found [here](). More options can be added to this
standard json file based on the requirement of the system.

For the experiments to be run in a local mode give the configs appropriately, for example use different data paths, different
disk partitions to mount on, different cpus to attach affinities to.

The Slooo code is the same irrespective of the mode the experiments are being run in.

Note: for local mode use ip as "localhost"

All the systems ported into Slooo inherited an [RSM class](utils/rsm.xsh) which is like a template. Following are the methods in the class:

1. init: The options from run.xsh are sent as kwargs to the RSM class. Also in this method the server_configs json file is
          parsed and stored in self.server_configs and self.client_config variables.

2. server_setup: This method takes care of setting up the servers on which the system processes are run. The setup can be
                 done either in memory or on disk, by default the setup is done on disk. This method sets up data directories
                 mounts them on required partitions using the required file system.
   
3. start_db: This method needs to be implemented in the child class as the code to start the system is different for each of the
             systems
   
4. db_init: 
                    

```
Command to run Slooo:

usage: xonsh run.xsh [-h] [--system SYSTEM] [--iters ITERS] [--workload WORKLOAD] 
[--server-configs SERVER_CONFIGS] [--runtime RUNTIME] [--exps EXPS] [--exp-type EXP_TYPE] 
[--swap] [--ondisk ONDISK] [--threads THREADS] [--diagnose] [--output-path OUTPUT_PATH] [--cleanup]

optional arguments:
  -h, --help            help
  --system SYSTEM       mongodb / rethinkdb / tidb / copilot
  --iters ITERS         number of iterations of the experiments to be ran
  --workload WORKLOAD   path to the workload for benchmarking (for ycsb)
  --server-configs SERVER_CONFIGS
                        server config path
  --runtime RUNTIME     runtime for the experiment
  --exps EXPS           experiments to be ran saperated by commas(,) (noslow, kill, 1, 2, 3, 4, 5, 6)
  --exp-type EXP_TYPE   leader / follower / both(for copilot)
  --swap                Swapniess on
  --ondisk ONDISK       in memory (mem) or on disk (disk)
  --threads THREADS     no. of logical clients
  --output-path OUTPUT_PATH
                        results output path
  --cleanup             clean's up the servers
  ```

```
Experiments vs codes:

noslow: no fault will be injected
kill: kills the desired node
1: cpu slow
2: cpu contention
3: disk slow
4: disk contention
5: memory contention
6: network slow (doesn't work in localmode)
```

The code for the faults can be found [here](faults/fault_inject.xsh)