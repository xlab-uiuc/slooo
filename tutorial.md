# A Tutorial of Using Slooo to Run Fault-Injection Testing for RethinkDB


This tutorial walks you through the process of using Slooo to do fault-injection testing. We choose RethinkDB, which implements the Raft consensus protocol.

We will run all the experiments in the pseudo-distributed mode, so you can follow the tutorial and run all the experiments on your own laptop/desktop.

Note: Slooo is written for a Debian based environment.

We will inject three types of faults:
- Node crash – killing a node
- Slow node – one of the node runs on a slow CPU
- Contended node – one of the node has memory contention

We will use YCSB as a client workload. 

Note that in Raft, there are two types of nodes, leader and follower. In this tutorial, we will inject the faults only to the follower node. You can do the leader experiments yourself.

### Clone the Slooo repo

```
git clone https://github.com/xlab-uiuc/slooo.git
```

### Xonsh setup
The tool uses Xonsh and a few other packages that come with a Python 3.6+ installation. To install Xonsh, please refer to [requirements](https://github.com/xlab-uiuc/slooo/blob/req_doc/requirements.md)

(optional) Editor and IDE support for Xonsh

Visual Studio Code
```
ext install jnoortheen.xonsh
```

Emacs

Add this line to your emacs configuration file:
```
(require 'xonsh-mode)
```

Vim

To add syntax highlight for xonsh in Vim,
```
git clone --depth 1 https://github.com/linkinpark342/xonsh-vim ~/.vim
```


### Server environment setup


Install these prerequisites :
```
sudo apt install tmux wget git --assume-yes
sudo apt-get install cgroup-tools --assume-yes
sudo apt-get install xfsprogs --assume-yes
```
Install rethinkdb 2.4.0 using the following command :
```
wget https://download.rethinkdb.com/repository/debian-buster/pool/r/rethinkdb/rethinkdb_2.4.0~0buster_amd64.deb
sudo apt install ./rethinkdb_2.4.0~0buster_amd64.deb --assume-yes
```

### Client environment setup

Install these prerequisites :
```
sudo apt install git default-jre --assume-yes
sudo apt install maven --assume-yes
pip3 install rethinkdb
sudo apt install jq --assume-yes
```

Installing the YCSB for rethinkdb:
```
git clone https://github.com/rethinkdb/YCSB.git
cd YCSB ; git apply ycsb_diff
mvn -pl com.yahoo.ycsb:rethinkdb-binding -am clean package -DskipTests
```
`YCSB/bin/ycsb` is the binary used to run benchmarking. 

Note: There seems to be an import issue with YCSB for rethink so copy the YCSB directory to Slooo directory and invoke the binary from there.

### Setting Server Config file
Before running the experiments a server config file needs to be filled based on the machine the tests are going to run.
A standard template for the server config file can be found [here](https://github.com/xlab-uiuc/slooo/blob/main/tests/rethink/server_configs_local.json)

The obvious point to consider is that there can't be any overlap in the configs between the pseudo nodes as all the nodes run 
on the same machine in localmode.

For example the cpu affinity we set to each of the node should be different, similarly the data paths should be different.
We've tried to name the configs in a way that they are self explainatory. The ycsb config in the client is meant to be the path to the ycsb binary.

### Run the tests

To perform tests, please invoke run.xsh. Below is an example usage of the script. 
```
usage: xonsh run.xsh [-h] [--system SYSTEM] [--iters ITERS] [--workload WORKLOAD] 
[--server-configs SERVER_CONFIGS] [--runtime RUNTIME] [--exps EXPS] [--exp-type EXP_TYPE] 
[--swap] [--ondisk ONDISK] [--threads THREADS] [--diagnose] [--output-path OUTPUT_PATH] [--cleanup]

optional arguments:
  -h, --help            help
  --system SYSTEM       mongodb / rethinkdb / tidb / copilot
  --iters ITERS         number of iterations
  --workload WORKLOAD   workload path
  --server-configs SERVER_CONFIGS
                        server config path
  --runtime RUNTIME     runtime
  --exps EXPS           experiments to be ran saperated by commas(,)
  --exp-type EXP_TYPE   leader / follower / both (for copilot)
  --swap                Swapniess on
  --ondisk ONDISK       in memory (mem) or on disk (disk)
  --threads THREADS     no. of logical clients
  --output-path OUTPUT_PATH
                        results output path
  --cleanup             clean up the servers
  ```
Note that you might have to add/delete arguments from the argument list above due to the need of specific quorum systems.
  
Here is a sample command to run rethinkdb tests : 
```bash
xonsh run.xsh –system rethinkdb --workload ./YCSB/workloads/workloada --server-configs ./rethinkdb/server_configs_local.json --runtime 300 --exp-type follower --exps noslow,kill,1,5 --iters 5 
```
```
Experiment codes:

noslow: no fault will be injected
kill: kills the desired node
1: cpu slow
2: cpu contention
3: disk slow
4: disk contention
5: memory contention
6: network slow (doesn't work in localmode)
```

The above command runs noslow, node kill, cpu slow, memory contention experiments in order over 5 trails. And it uses the `./YCSB/workloads/workloada` as the workload, `./rethinkdb/server_configs_local.json` as the server configs file and for a runtime for 300 seconds. And the results by default are stored in the results directory.

The script instantiates multiple DB class instances according to the number of iterations and experiments specified, and invokes the ‘run’ method in the DB class to start the testing procedure. 

Note: Clear up old results as the results get overwritten.


### Porting a new Quorum System

Please walk people over how to write the testing scripts, based on
https://github.com/xlab-uiuc/slooo/blob/main/rethink/rethink.xsh
https://github.com/xlab-uiuc/slooo/blob/main/rethink/local_server_configs.json

Please answer the following two questions:
What need to be written
How to write them

Please explain well.

### Check the results