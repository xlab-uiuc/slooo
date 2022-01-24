# Tutorial: Using Slooo to Run Fault-Injection Testing for RethinkDB

This tutorial walks you through the process of using Slooo to do fault-injection testing. We choose [RethinkDB](https://rethinkdb.com/), 
which implements [the Raft consensus protocol](https://raft.github.io/).

In this tutorial, We will run all the experiments in the "pseudo-distributed" mode. So, you can follow the tutorial and run all the experiments on your own laptop/desktop.

We will inject three types of faults:
- Node crash – killing a node
- Slow node – one of the node runs on a slow CPU
- Contended node – one of the node has memory contention

We will use [YCSB](https://github.com/brianfrankcooper/YCSB) as the client workload to measure performance. 

Note that in Raft, there are two types of nodes, leader and follower. In this tutorial, we will inject the faults only to the follower node. You can do the leader experiments yourself.

## 1. Clone the Slooo repo

```
$ git clone https://github.com/xlab-uiuc/slooo.git
```

## 2. Setup environment

We assume a Debain-based Linux distribution. If you use other Linux distro, please install the packages accordingly.

Install packages:
```
$ sudo apt install tmux wget --assume-yes
$ sudo apt-get install cgroup-tools --assume-yes
$ sudo apt-get install xfsprogs --assume-yes
```

Install RethinkDB 2.4.0:
```
$ wget https://download.rethinkdb.com/repository/debian-buster/pool/r/rethinkdb/rethinkdb_2.4.0~0buster_amd64.deb
$ sudo apt install ./rethinkdb_2.4.0~0buster_amd64.deb --assume-yes
```

Install more packages:
```
$ sudo apt install default-jre --assume-yes
$ sudo apt install maven --assume-yes
$ pip3 install rethinkdb
```

Installing the YCSB for RethinkDB:
```
$ git clone https://github.com/rethinkdb/YCSB.git
$ cd YCSB ; git apply ycsb_diff
$ mvn -pl com.yahoo.ycsb:rethinkdb-binding -am clean package -DskipTests
```
`YCSB/bin/ycsb` is the binary used to run benchmarking.

Note: We encountered some configuration issue with YCSB for RethinkDB, so we copy the YCSB dir into Slooo directory and invoke the binary from there.


## 3. Writing the testing scripts

Slooo is not magic. It essentially provides some common utilities to write the fault-injection tests in a structured way. Those utilities are implemented here,

https://github.com/xlab-uiuc/slooo/tree/main/utils

Please feel free to extend the utilities and send us PRs.

To test a specific system, you need to implement a few interfaces, because different systems have different ways to start, terminate, and configure its components. 

The test procedure for quorum systems can be seen at: 

https://github.com/xlab-uiuc/slooo/blob/main/utils/quorum.xsh#L45-L62

So, to test RethinkDB, we just need to implement a RethinkDB class that inherits the abstract Quorum class and write the RethinkDB-specific code there,

https://github.com/xlab-uiuc/slooo/blob/main/tests/rethink/test_main.xsh

You will also need to specify the configuration for the RethinkDB under test. Slooo will parse the configurations and load them to the RethinkDB instances. The configuration file for a local test is,

https://github.com/xlab-uiuc/slooo/blob/main/tests/rethink/server_configs_local.json


If you want to inject more faults, check:

https://github.com/xlab-uiuc/slooo/blob/main/faults/fault_inject.xsh


## 4. Run the tests

We prepared an CLI command to run the tests:
```
$ xonsh run.xsh –system rethinkdb --workload ./YCSB/workloads/workloada --server-configs ./rethinkdb/server_configs_local.json --runtime 300 --exp-type follower --exps noslow,kill,1,5 --iters 5
```

## 5. Check the results

After each of the tests is finished, the results are dumped to the `Slooo/results` (the path can be configured using `--output-path option`).

## 6. Slooo in Docker

TBD
