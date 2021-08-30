import json
import logging
import argparse

from utils.general import *
from utils.constants import *

class Redis:
    def __init__(self, **kwargs):
        opt = kwargs.get("opt")
        self.exp_type = "noslow" if opt.exp_type == "" else opt.exp_type
        self.server_configs, self.servermap = config_parser(opt.server_configs)
        self.clean = opt.cleanup 
        self.benchmark = opt.benchmark
        self.sentinel = opt.sentinel
        self._exps = opt.exps

        # TODO: seperate _exps into list by commas.


    # Setup VM's by installing dependences
    def install_deps(self):
        for server_config in self.server_configs:

            serv_addr = "redis@" + str(server_config["privateip"])
            
            ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa @(serv_addr) "sudo sh 'sudo apt install tmux wget git gcc make cgroup-tools xfsprogs libc6 python python3 numactl --assume-yes'"
            # Download and install Redis source to VM.
            ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa @(serv_addr) "sudo sh -c 'rm -rf redis ;  wget https://download.redis.io/releases/redis-6.2.4.tar.gz ; tar xvf redis-6.2.4.tar.gz ; mv redis-6.2.4 redis ; cd redis ; make'"
            
            
            #sync clocks - https://www.cockroachlabs.com/docs/stable/deploy-cockroachdb-on-microsoft-azure-insecure.html
	        # todo: specially for azure
  	        ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa @(serv_addr) "sudo sh -c 'curl -o https://raw.githubusercontent.com/torvalds/linux/master/tools/hv/lsvmbus'"
  	        devid=$( StrictHostKeyChecking=no)
	        ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa @(serv_addr) "sudo sh -c 'echo "$devid" | sudo tee /sys/bus/vmbus/drivers/hv_util/unbind'"
  	        ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa @(serv_addr) "sudo sh -c 'sudo apt-get install ntp ntpstat --assume-yes ; sudo service ntp stop ; sudo ntpd -b time.google.com'"
  	        ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa @(serv_addr) "sudo sh -c 'echo -e \"server time1.google.com iburst\nserver time2.google.com iburst\nserver time3.google.com iburst\nserver time4.google.com iburst\" >> /etc/ntp.conf'"
  	        ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa @(serv_addr) "sudo sh -c 'sudo service ntp start ; ntpstat ; true'"
    	    # scp disablethp redis@"${servernameipmap[$key]}":~/
    	    ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa @(serv_addr) "sudo cp disablethp /etc/systemd/system/disable-transparent-huge-pages.service"
    	    ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa @(serv_addr) "sudo systemctl daemon-reload ; sudo systemctl start disable-transparent-huge-pages ; cat /sys/kernel/mm/transparent_hugepage/enabled ; sudo systemctl enable disable-transparent-huge-pages"
    	    # todo: azure specific settings
    	    ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa @(serv_addr) "sudo sysctl -w net.ipv4.tcp_keepalive_time=120"
    	    ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa @(serv_addr) "sudo echo 'net.ipv4.tcp_keepalive_time = 120' | sudo tee /etc/sysctl.conf"


        	# Make Redis folder accesible so can scp files.
	        ssh -i ~/.ssh/id_rsa @(serv_addr) "sudo chmod 777 /home/redis/redis"


    # Initialize db servers 
    def init(self):
        start_servers(self.server_configs) 
    
    def slowness_inject(self):
        pass
    def cleanup(self):
        for serv_conf in self.server_configs: 
            ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa @("redis@" + str(serv_conf["privateip"])) 'sudo cgdelete cpu:db cpu:cpulow cpu:cpuhigh blkio:db memory:db ; true'
	        ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa @("redis@" + str(serv_conf["privateip"])) 'sudo /sbin/tc qdisc del dev eth0 root ; true' 
    
    
    # Make follower, leader VM chosen randomly???
    def gen_vm_info(self):
        for server_config in self.server_configs:
            suffix =  server_config[len(server_config)-1] 
            if suffix == '1':
                self.leader_server_config = server_config
            elif suffix == '2'
                self.follower_server_config = server_config


    def start_db():
        # TODO: Make directory for redis config files
        # Start leader instance. 
        if self.sentinel == False: 
            scp -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no redis_master_confs/redis_master_1.conf @("redis@" + self.leader_server_config["privateip"] + ":/home/redis/redis")  
            ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no @("redis@" + self.leader_server_config["privateip"]) 'sudo numactl --physcpubind=0 /home/redis/redis/src/redis-server /home/redis/redis/redis_master_1.conf' 
        else 
            scp -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no sentinel_master_template.conf @("redis@" + self.leader_server_config["privateip"] + ":/home/redis/redis")  
            ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no @("redis@" + self.leader_server_config["privateip"]) 'sudo numactl --physcpubind=0 /home/redis/redis/src/redis-server /home/redis/sentinel_master_template.conf --sentinel' 

        # Start follower instances.
        for server_config in self.server_configs:
            if server_config["privateip"] != leader_server_config["privateip"]:
                vm_name = server_config['name']  
                conf_n = int(vm_name[vm_name.find('-')+1:len(vm_name)])
                if self.sentinel: 
                    scp -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no sentinel_follower_template.conf @("redis@" + server_config["privateip"] + ":/home/redis/redis")                         
                    ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no @("redis@" + server_config["privateip"]) 'sudo numactl --physcpubind=0 /home/redis/redis/src/redis-server /home/redis/redis/sentinel_follower_template.conf --sentinel'
                # TODO: Non-sentinel case.
                #else:

    def run(self):
        #if self.clean: 
        #    self.cleanup() 
        self.cleanup()
        slef.gen_vm_info()

def parse_opt():
    parser = argparse.ArgumentParser()
    
    parser.add_argument("--server-configs", type=str, default="./server_configs.json", help="server config path")
    parser.add_argument("--iters", type=int, default=1, help="number of iterations")
    parser.add_argument("--exps", type=str, default="noslow", help="experiments to be ran saperated by commas(,)")
    parser.add_argument("--exp-type", type=str, default="", help="leader/follower")
    parser.add_argument("--cleanup", type=bool, default=False, help="clean's up the servers")

    # Custom options specfically for Redis
    parser.add_argument('--benchmark', type=str, default='redis-benchmark' help='redis-benchmark/memtier-benchmark')
    parser.add_argument('--sentinel',  type=bool, default=False, help="make all VM's Redis Sentinels.")

    opt = parser.parse_args()
    return opt

def main(opt):
    if opt.cleanup:
        rd = Redis(opt=opt)
        rd.cleanup()
        return 

if __name__ == "main":
