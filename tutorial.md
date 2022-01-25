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
## 1. Clone the Slooo repo

```
git clone https://github.com/xlab-uiuc/slooo.git
```

## 2. Environment Setup

We assume a Debain-based Linux distribution. If you use other Linux distro, please install the packages accordingly.

### Sudo
Running slooo under the "pseudo-distributed" mode requires to switch to a sudoer because a lot of commands (like the cgroup ones) requires sudo previleges. **If you hate sudoers, please jump to [Slooo in Docker](#slooo_docker)**

To run SSH without authentication

```
ssh-keygen -t rsa
```

Ignore this step if you have the key present already.

```
cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
```

Assign root using following commands:

Open the `/etc/sudoers` file by running

```
sudo visudo
```

At the end of the /etc/sudoers file, add

```
username     ALL=(ALL) NOPASSWD:ALL
```

Replace username with your account username Save the file and exit.

Now you can run sudo commands without password (which makes it easier to run Slooo).

### Xonsh
The slooo tool relies on a Python3.6+ installation and the following Python3 packages to function.

- json
- yaml
- argparse
- xonsh

To install those packages, you need to have python3.6+ and pip3 installed on your machine.
Then you can copy the code below to install xonsh.

```shell
pip3 install 'xonsh[full]'
```
Note that `json`, `yaml` and `argparse` are built-in packages of Python3, which should eliminate the need to install them. *But please install them as well if you encountered any trouble.*


### Installation Verification
Type `xonsh` in terminal to see if you have successfully installed it. If not, please add xonsh executable file to PATH.

```shell
echo 'export PATH="$USER/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```


For more information on how to install xonsh and use xonsh, please go to [xonsh](https://xon.sh).

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
xonsh run.xsh --system rethinkdb --workload ./YCSB/workloads/workloada --server-configs ./rethinkdb/server_configs_local.json --runtime 300 --exp-type follower --exps noslow,kill,1,5 --iters 5
```

For more options check : [https://github.com/xlab-uiuc/slooo/blob/c0746dcc83944a573b8d4a200df5813267c5e43e/run.xsh#L11-L22
](https://github.com/xlab-uiuc/slooo/blob/c0746dcc83944a573b8d4a200df5813267c5e43e/run.xsh#L11-L22)

For more faults check : [https://github.com/xlab-uiuc/slooo/blob/7fc1011f8984571b4a11afb2ab1dfceea70538e5/faults/fault_inject.xsh#L57-L62](https://github.com/xlab-uiuc/slooo/blob/7fc1011f8984571b4a11afb2ab1dfceea70538e5/faults/fault_inject.xsh#L57-L62)

## 5. Check the results

After each of the tests is finished, the results are dumped to the `Slooo/results` (the path can be configured using `--output-path option`).

<span id="slooo_docker"></span>

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
