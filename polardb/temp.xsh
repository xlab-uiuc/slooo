#!/usr/bin/env xonsh

import sys,os,json
import logging
import argparse

from utils.rsm import RSM
from utils.general import *
from utils.constants import *
from resources.slowness.slow import slow_inject

class PolarDB(RSM):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        #TODO workload used as pgbench's scale factor
        self.pgbench_scalefactor = int(self.workload)
        
        #TODO revisit here for result / figure generation
        self.results_path = os.path.join(self.output_path, "polardb_{}_{}_{}_{}_results".format(self.exp_type, "swapon" if self.swap else "swapoff", self.ondisk, self.threads))
        mkdir -p @(self.results_path)
        self.results_text = os.path.join(self.results_path, f"{self.exp}_{self.trial}.txt")

        
        self.masterip = self.server_configs[0]["privateip"] 
        self.followerip = self.server_configs[1]["privateip"]
        self.learnerip = self.server_configs[2]["privateip"]
        self.slowdownip = None
        
        #TODO Revisit here (since it is included in new server)_configs.json)
        self.pidslist = []
        self.ppidlist = []
    #  # cleans up the data  storage directories
    # def polar_data_cleanup():
    #     data_cleanup(self.server_configs)

    # init is called to initialize the db servers
    def server_setup(self):
        # TODO revisit here
        super().server_setup()
        for server_config in self.server_configs:
            ip = server_config["privateip"]
            dbpath = server_config["dbpath"]
            ssh -i ~/.ssh/id_rsa @(ip) @(f"sudo sh -c 'sudo mkdir {dbpath};\
                                                     sudo chmod o+w {dbpath}'")
    
    # start_db starts the databse instances on each of the server by using pgxc_ctl on the master node to initiate the cluster
    def start_db(self):
        ssh @(self.masterip) "pgxc_ctl -c ~/polardb/paxos_multi.conf init force all"
        ssh @(self.masterip) "psql -p 10001 -d postgres -c 'create database pgbench;'"
    # 
    def get_pidslist(self):
        # NOTE: POLARDB SPECIFIC
	# TODO: The following information can also be grepped from server_config["process"]
        for server_config in self.server_configs:
	    ppid_str = $(ssh @(server_config["privateip"]) f"ps -ef | grep {server_config['process']} | grep {server_config['role']}")
            ppid_str = ppid_str.split('\n')[0]
            ppid_str = ppid_str.split()[1]
            self.ppidlist.append(ppid_str)
	    pids_str = ppid_str + '\n' + $(ssh @(server_config["privateip"]) f"pgrep -P {ppid_str}")
            self.pidslist.append(pids_str)

    def set_affinity(self):
        # TODO: MODIFY THIS
        for i, server_config in enumerate(self.server_configs):
            cpu = server_config["cpu"]
            for pid in self.pidslist[i].split():
                ssh @(server_config["privateip"]) @(f"taskset -acp {cpu} {pid}")

    def db_init(self):
        if self.exp_type == "leader":
            self.slowdownip = self.masterip
        elif self.exp_type == "follower":
            self.slowdownip = self.followerip
        elif self.exp_type == "learner":
            self.slowdownip = self.learnerip
        else: 
            pass
            # nothing to do 
            # input checking should be done at the instantination of the class object


    def pgbench_load(self):
        ssh @(self.masterip) @(f"pgbench -i -s {self.pgbench_scalefactor} -p 10001 -d pgbench")

    def pgbench_run(self):
        ssh @(self.masterip) "rm -rf ~/trial* ~/Trial"


        tmp_out = $(ssh @(self.masterip) @(f"pgbench -M prepared -r -c {self.threads} -j 1 -T {self.runtime} -p 10001 -d pgbench -l --log-prefix=trial | tail -n22")) 
        ssh @(self.masterip) "cat trial* > Trial"
        num_tran = int($(ssh @(self.masterip) "cat Trial* | wc").split()[0])
 
        # P99 calculation
        p99 = float($(ssh @(self.masterip) @("sort ~/Trial* -k3rn|head -n {} |tail -n 1".format(int(num_tran/100)))).split()[2])

        p99_9 = float($(ssh @(self.masterip) @("sort ~/Trial* -k3rn|head -n {} |tail -n 1".format(int(num_tran/1000)))).split()[2])
        p50 = float($(ssh @(self.masterip) @("sort ~/Trial* -k3rn|head -n {} |tail -n 1".format(int(num_tran/2)))).split()[2])
        
        self.result_gen(self.results_text, tmp_out, self.exp_type, self.exp, p99_9, p99, p50) #TODO use varshith's plot function

        
            
    def polar_cleanup(self):
        ssh @(self.masterip) "pgxc_ctl -c ~/polardb/paxos_multi.conf clean all"


    def run(self):
        start_servers(self.server_configs)
        super().server_cleanup()
        self.start_db()
        self.db_init()
        self.pgbench_load()
        # TODO adapt to local mode please
        self.get_pidslist()
        self.set_affinity()
        
        if self.exp_type != "noslow" and self.exp !="noslow":
             
            self.slowdownpids = $(ssh @(self.slowdownip) "pgrep postgres")
            slow_inject(self.exp, HOSTID, self.slowdownip, self.slowdownpids) # CPU
        
        self.pgbench_run()
        
        self.polar_cleanup()
        super().server_cleanup()
        stop_servers(self.server_configs)
    
    def result_med_gen(results_path, iters, expno):
	if results_path[-1] != "/":
	    results_path += "/"

	dict_arr = []
	for i in range(1, iters+1):
	    with open(results_path + "{}_{}.txt".format(expno, i), 'r') as file_input:
		dict_json_tmp = json.load(file_input)
		dict_arr.append(dict_json_tmp)

		# dict_json['OVERALL']['Throughput'] += dict_json_tmp['OVERALL']['Throughput']
		# dict_json['OVERALL']['Latency'] += dict_json_tmp['OVERALL']['Latency']
		# dict_json['OVERALL']['P99 Latency'] += dict_json_tmp['OVERALL']['P99 Latency']
		# dict_json['OVERALL']['P50 Latency'] += dict_json_tmp['OVERALL']['P50 Latency']
		# for k in dict_json['SPECIFIC (Latency)'].keys():
		#     dict_json['SPECIFIC (Latency)'][k] += dict_json_tmp['SPECIFIC (Latency)'][k]
	dict_json = dict_arr[0]
	for k in dict_json["OVERALL"].keys():
	    temp_arr = []
	    for i in range(0,iters):
		temp_arr.append(dict_arr[i]["OVERALL"][k])
	    temp_arr.sort()
	    if int(iters / 2 * 2) == iters:
		dict_json["OVERALL"][k] = (temp_arr[int(iters / 2)] + temp_arr[int(iters / 2 - 1)]) / 2
	    else:
		dict_json["OVERALL"][k] = temp_arr[int((iters - 1) / 2)]

	for k in dict_json["SPECIFIC (Latency)"].keys():
	    temp_arr = []
	    for i in range(0,iters):
		temp_arr.append(dict_arr[i]["SPECIFIC (Latency)"][k])
	    temp_arr.sort()
	    if int(iters / 2 * 2) == iters:
		dict_json["SPECIFIC (Latency)"][k] = (temp_arr[int(iters / 2)] + temp_arr[int(iters / 2 - 1)]) / 2
	    else:
		dict_json["SPECIFIC (Latency)"][k] = temp_arr[int((iters - 1) / 2)]


	result_in_json = json.dumps(dict_json, skipkeys = True, allow_nan = True, indent = 4)

	with open(results_path + "{}_".format(expno) + "med.txt", 'w') as result:
	    result.write(result_in_json)

    def result_gen(result_path, tmp_out, slow_type, expno, p99_9, p99, p50):
	specific = []
	print(tmp_out)
	tmp_out = tmp_out.split('\n')
	for i,line in enumerate(tmp_out):
	    if i == 1:
		scaling_factor = line[16:].strip()
	    elif i == 3:
		clients = line[19:].strip()
	    elif i == 4:
		threads = line[19:].strip()
	    elif i == 7:
		o_latency = line[18: -3].strip()
	    elif i == 8:
		o_throughput = line[6: -37].strip()
	    elif 10 < i:
		specific.append(line.strip()[0:7].strip())
	    else:
		continue

	result = {
	    "SYS Setup" : {
		"Clients"   : clients,
		"Threads"   : threads,
		"Slow Type" : slow_type,
		"Expno"     : expno,
		"Scaling Factor": scaling_factor
	    },
	    "OVERALL"   : {
		"Throughput": float(o_throughput),
		"Latency"   : float(o_latency),
		"P99.9 Latency": float(p99_9),
		"P99 Latency" : float(p99),
		"P50 Latency" : float(p50)
	    },
	    "SPECIFIC (Latency)"  : {
		"\\set aid random(1, 100000 * :scale)" : float(specific[0]),
		"\\set bid random(1, 1 * :scale)" : float(specific[1]),
		"\\set tid random(1, 10 * :scale)" : float(specific[2]),
		"\\set delta random(-5000, 5000)" : float(specific[3]),
		"BEGIN;" : float(specific[4]),
		"UPDATE pgbench_accounts SET abalance = abalance + :delta WHERE aid = :aid;" : float(specific[5]),
		"SELECT abalance FROM pgbench_accounts WHERE aid = :aid;" : float(specific[6]),
		"UPDATE pgbench_tellers SET tbalance = tbalance + :delta WHERE tid = :tid;" : float(specific[7]),
		"UPDATE pgbench_branches SET bbalance = bbalance + :delta WHERE bid = :bid;" : float(specific[8]),
		"INSERT INTO pgbench_history (tid, bid, aid, delta, mtime) VALUES (:tid, :bid, :aid, :delta, CURRENT_TIMESTAMP);" : float(specific[9]),
		"END;" : float(specific[10])
	    }
	}

	result_in_json = json.dumps(result, skipkeys = True, allow_nan = True, indent = 4)

	with open(result_path, 'w') as result:
	    result.write(result_in_json)
