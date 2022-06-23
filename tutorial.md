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

---
Check out [Slooo in Docker](#slooo_docker) if you want to skip 1 & 2  

For any problem encountered along the way, check out this [FAQ document](https://github.com/xlab-uiuc/slooo/blob/main/FAQ.md). 

## 1. Clone the Slooo repo

```
git clone https://github.com/xlab-uiuc/slooo.git
```

## 2. Environment Setup

We assume a Debain-based Linux distribution. If you use other Linux distro, please install the packages accordingly.

Steps below are only specific to RethinkDB. Please fulfil [generic requirements of the slooo tool](https://github.com/xlab-uiuc/slooo/blob/main/requirements.md) here before proceeding. 

---
Install packages:
```
sudo apt install tmux wget --assume-yes
sudo apt-get install cgroup-tools --assume-yes
sudo apt-get install xfsprogs --assume-yes
```

Install RethinkDB 2.4.0:
```
wget https://download.rethinkdb.com/repository/debian-buster/pool/r/rethinkdb/rethinkdb_2.4.0~0buster_amd64.deb
sudo apt install ./rethinkdb_2.4.0~0buster_amd64.deb --assume-yes
```

Install more packages:
```
sudo apt install default-jre --assume-yes
sudo apt install maven --assume-yes
pip3 install rethinkdb
```

Installing the YCSB for RethinkDB:
```
git clone https://github.com/rethinkdb/YCSB.git
cd YCSB ; git apply <path to rethink_ycsb_diff> # can be found at https://github.com/xlab-uiuc/slooo/blob/main/utils/rethink_ycsb_diff 
mvn -pl com.yahoo.ycsb:rethinkdb-binding -am clean package -DskipTests
```
`YCSB/bin/ycsb` is the binary used to run benchmarking.

Note: We encountered some configuration issue with YCSB for RethinkDB, so we copy the YCSB dir into Slooo directory and invoke the binary from there.

One should also add the slooo directory to PYTHONPATH, for example
```
export PYTHONPATH=”<path to slooo>:$PYTHONPATH”
```


## 3. Writing the testing scripts

Slooo is not magic. It essentially provides some good abstractions to use which makes it easier to run fault tolorence tests on different systems and makes it eaiser to port to Slooo.

https://github.com/xlab-uiuc/slooo/tree/main/structures

Please feel free to extend the utilities and send us PRs.

To test a specific system, you need to implement a few interfaces, because different systems have different ways to start, terminate, and configure its components. 


So, to test RethinkDB, we just need to implement a RethinkDB class that inherits the abstract Quorum class and write the RethinkDB-specific code there,

https://github.com/xlab-uiuc/slooo/blob/main/quorums/rethink/test_main.xsh

RethinkDB's code can act as a good template for users trying to port a new system.

You will also need to specify the configuration for the RethinkDB under test. Slooo will parse the configurations and load them to the RethinkDB instances. The configuration file for a local test is,

https://github.com/xlab-uiuc/slooo/blob/main/quorums/rethink/node_configs.yaml 


If you want to inject more faults, check:

https://github.com/xlab-uiuc/slooo/blob/main/faults/fault_inject.xsh


## 4. Run the tests

We prepared an CLI command to run the tests:
```
To run the tests mentioned in ./utils/run.yaml
xonsh run.xsh --run-configs ./utils/run.yaml

To cleanup the nodes:
xonsh run.xsh --run-configs ./utils/run.yaml --cleanup
```
The user needs to update run.yaml according to the requirments first

To understand the CLI better check:
https://github.com/xlab-uiuc/slooo/blob/main/run.xsh


For more faults check : [https://github.com/xlab-uiuc/slooo/blob/6bd8ff9e1978f7f7fa4c6a46b4f0f3de7719ecca/faults/fault_inject.xsh#L86-L92](https://github.com/xlab-uiuc/slooo/blob/6bd8ff9e1978f7f7fa4c6a46b4f0f3de7719ecca/faults/fault_inject.xsh#L86-L92)

## 5. Check the results

After each of the tests is finished, the results are dumped to the path provided in run.yaml (output_dir option)

<!-- <span id="slooo_docker"></span> -->

## 6. Slooo in Docker
We have prepared a docker image which has all environment setup done (for RethinkDB) to ease your pain. 

You can access the image from a copy on [GoogleDrive](https://drive.google.com/file/d/1DaJuOh2rXvvXfBAoPWzjTtMPbSgxaJ4Z/view?usp=sharing) or from DockerHub by executing 
```
docker pull eisvogle/slooo
```
We recommend accessing the image from DockerHub in case of any update of the slooo tool.

Note that:
- slooo repo can be found in ~ path inside the container
- User needs to run `sudo /etc/init.d/ssh` start  inside the container to start the ssh server

## Appendix: Editor and IDE support for Xonsh
### Visual Studio Code
```
ext install jnoortheen.xonsh
```

### Emacs
Add this line to your emacs configuration file
```
(require 'xonsh-mode)
```

### Vim
To add syntax highlight support for xonsh, execute
```
git clone --depth 1 https://github.com/linkinpark342/xonsh-vim ~/.vim
```
