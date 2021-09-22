#!/usr/bin/env xonsh

import os
import json
from utils.constants import *

# create the some number of vms with the naming convention
# <database name>_<prefix name>_<server number/"client">

def create_vms(numVM, database, prefix):
    # Generate custom ssh keys for VM's, or just use users' exisitng ones?
    
    # create client VM
    az vm create --name @(database + "_" + prefix + "_client") --resource-group @(RESOURCE_GROUP) --subscription @(SUBSCRIPTION) --zone @(ZONE) --image @(IMAGE) --os-disk-size-gb @(OS_DISK_SIZE) --data-disk-sizes-gb @(DATA_DISK_SIZE) --storage-sku @(STORAGE_SKU) --size @(VM_TYPE) --admin-username @(database) --ssh-key-values ~/.ssh/id_rsa.pub --accelerated-networking true


    # run ssh-keygen on client vm
    clientConf = $(az vm list-ip-addresses --subscription @(SUBSCRIPTION) --name @(database + "_" + prefix + "_client") --query '[0].{name:virtualMachine.name, privateip:virtualMachine.network.privateIpAddresses[0], publicip:virtualMachine.network.publicIpAddresses[0].ipAddress}' -o json)
    clientConfig = json.load(clientConf)
    clientPublicIP = clientConfig["publicip"]

    ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa @(database + "@" + clientPublicIp) 'ssh-keygen -t rsa -f ~/.ssh/id_rsa -q -P "" <<<y 2>&1 >/dev/null '

    # scp client id_rsa.pub to local directory.
    scp @(database + "@" + clientPublicIP):~/.ssh/id_rsa.pub ./client_rsa.pub

    # Create servers with both local ssh key and client VM ssh key
    for i in range(0, numVM):
        az vm create --name @(database + "_" + prefix + str(i)) --resource-group @(RESOURCE_GROUP) --subscription @(SUBSCRIPTION) --zone @(ZONE) --image @(IMAGE) --os-disk-size-gb @(OS_DISK_SIZE) --data-disk-sizes-gb @(DATA_DISK_SIZE) --storage-sku @(STORAGE_SKU) --size @(VM_TYPE) --admin-username @(database) --ssh-key-values ~/.ssh/id_rsa.pub --accelerated-networking true



def delete_vms(path):
    with open(path) as f:
        servers = json.load(f)
        for server in servers:
            az vm delete --name @(server["name"]) --resource-group @(RESOURCE_GROUP) --subscription @(SUBSCRIPTION)--yes



# reads the server_config json to a list of dictionaries
def config_parser(path):
    server_configs = []
    servermap = {}
    with open(path) as f:
        nodes = json.load(f)
        servers = nodes["servers"]
        for server in servers:
            server_configs.append(server)
            servermap[server["name"]] = server
            servermap[server["name"]+":27017"] = server   ####revist
            servermap[server["privateip"]] = server

    return server_configs, servermap, nodes

# starts the servers
def start_servers(server_configs):
    for server_config in server_configs:
        az vm start --resource-group @(RESOURCE_GROUP) --subscription @(SUBSCRIPTION) --name @(server_config["name"])

# stops the servers
def stop_servers(server_configs):
    for server_config in server_configs:
        az vm deallocate --resource-group @(RESOURCE_GROUP) --subscription @(SUBSCRIPTION) --name @(server_config["name"])


# def config_client():
def config_servers(database, server_configs):
    for serv_conf in server_configs:
        ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa @(database + "@" + serv_conf["privateip"]) 'xonsh' < setup/@(database)_setup.xsh


# #cleans up the data storage directories
def data_cleanup(server_configs, data_path):
    for server_config in server_configs:
        ssh -i ~/.ssh/id_rsa @(server_config["privateip"]) @("sh -c 'sudo rm -rf {}'".format(data_path))



# init_disk is called to create and mount directories on disk
#partition_name="/dev/sdc1"
# bs=1000
# **revist** make the code kwargs compatible
def init_disk(server_configs, data_path, partition_name, file_system, exp, bs, count):
	for server_config in server_configs:
		ssh -i ~/.ssh/id_rsa @(server_config["privateip"]) @(f"sudo sh -c 'sudo umount {partition_name} ; sudo mkdir -p {data_path} ; sudo mkfs.{file_system} {partition_name} -f ; sudo mount -t {file_system} {partition_name} {data_path} ; sudo mount -t xfs {partition_name} {data_path} -o remount,noatime ; sudo chmod o+w {data_path}'")

		if exp=="4":
			ssh -i ~/.ssh/id_rsa @(server_config["privateip"]) @(f"sh -c 'taskset -ac 1 dd if=/dev/zero of={data_path}/tmp.txt bs={bs} count={count} conv=notrunc'")

def init_memory(server_configs, data_path):
	for server_config in server_configs:
		ssh -i ~/.ssh/id_rsa @(server_config["privateip"]) @(f"sudo sh -c 'sudo mkdir -p {data_path} ; sudo mount -t tmpfs -o rw,size=8G tmpfs {data_path} ; sudo chmod o+w {data_path}'")


def set_swap_config(server_configs, swap, data_path="", bs="", count=""):
	# swappiness config
	if not swap:
		for server_config in server_configs:
			ssh -i ~/.ssh/id_rsa @(server_config["privateip"]) "sudo sh -c 'sudo sysctl vm.swappiness=0 ; sudo swapoff -a && swapon -a'"
	else:
		for server_config in server_configs:
			ssh -i ~/.ssh/id_rsa @(server_config["privateip"]) @(f"sudo sh -c 'sudo dd if=/dev/zero of={data_path} bs={bs} count={count} ; sudo chmod 600 {data_path} ; sudo mkswap {data_path}'")  # 24 GB
			ssh -i ~/.ssh/id_rsa @(server_config["privateip"]) @(f"sudo sh -c 'sudo sysctl vm.swappiness=60 ; sudo swapoff -a && sudo swapon -a ; sudo swapon {data_path}'")


def cleanup(server_configs, data_path, partition_name, process, swap, swapfile=""):
    for server_config in server_configs:
        ssh -i ~/.ssh/id_rsa @(server_config["privateip"]) @(f"sudo sh -c 'sudo rm -rf {data_path} ; sudo umount {partition_name} ; sudo cgdelete cpu:db cpu:cpulow cpu:cpuhigh blkio:db ; true'")
        ssh -i ~/.ssh/id_rsa @(server_config["privateip"]) "sudo sh -c 'sudo /sbin/tc qdisc del dev eth0 root ; true'"
        ssh -i ~/.ssh/id_rsa @(server_config["privateip"]) @(f"sudo sh -c 'pkill {process}'")
        if swap:
            ssh -i ~/.ssh/id_rsa @(server_config["privateip"]) @(f"sudo sh -c 'sudo swapoff -v {swapfile}'")
