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
    with open(path) as f:
        nodes = json.load(f)

    return nodes

# starts the servers
def start_servers(server_configs):
    for server_config in server_configs:
        if server_config["privateip"] == "localhost":
            continue
        az vm start --resource-group @(RESOURCE_GROUP) --subscription @(SUBSCRIPTION) --name @(server_config["name"])

# stops the servers
def stop_servers(server_configs):
    for server_config in server_configs:
        if server_config["privateip"] == "localhost":
            continue
        az vm deallocate --resource-group @(RESOURCE_GROUP) --subscription @(SUBSCRIPTION) --name @(server_config["name"])


# def config_client():
def config_servers(database, server_configs):
    for serv_conf in server_configs:
        ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa @(database + "@" + serv_conf["privateip"]) 'xonsh' < setup/@(database)_setup.xsh


# # #cleans up the data storage directories
# def data_cleanup(server_configs):
#     for server_config in server_configs:
#         ssh -i ~/.ssh/id_rsa @(server_config["privateip"]) @(f"sh -c 'sudo rm -rf {server_configs["data_path"]}'")



# init_disk is called to create and mount directories on disk
def init_disk(server_configs, exp):
	for server_config in server_configs:
        ip = server_config["privateip"]
        partition = server_config["partition"]
        datadir = server_config["datadir"]
        filesys = server_config["file_system"]

		ssh -i ~/.ssh/id_rsa @(ip) @(f"sudo sh -c 'sudo umount {partition} ;\
                                        sudo mkdir -p {datadir} ;\
                                        sudo mkfs.{filesys} {partition} -f ;\
                                        sudo mount -t {filesys} {partition} {datadir} ;\
                                        sudo mount -t xfs {partition} {datadir} -o remount,noatime ;\
                                        sudo chmod o+w {datadir}'")

		if exp=="4":
			ssh -i ~/.ssh/id_rsa @(ip) @(f"sh -c 'taskset -ac 1 dd if=/dev/zero of={datadir}/tmp.txt bs=1000 count=1400000 conv=notrunc'")

def init_memory(server_configs, data_path):
	for server_config in server_configs:
		ssh -i ~/.ssh/id_rsa @(server_config["privateip"]) @(f"sudo sh -c 'sudo mkdir -p {data_path} ; sudo mount -t tmpfs -o rw,size=8G tmpfs {data_path} ; sudo chmod o+w {data_path}'")

# swappiness config
def set_swap_config(server_configs, swap):
	if swap:
        for server_config in server_configs:
            ip = server_config["privateip"]
            swapfile = server_config["swapfile"]
            swapbs = server_config["swapbs"]
            swapcount = server_config["swapcount"]

			ssh -i ~/.ssh/id_rsa @(ip) @(f"sudo sh -c 'sudo dd if=/dev/zero of={swapfile} bs={swapbs} count={swapcount} ;\
                                           sudo chmod 600 {swapfile} ; sudo mkswap {swapfile}'")
			ssh -i ~/.ssh/id_rsa @(ip) @(f"sudo sh -c 'sudo sysctl vm.swappiness=60 ;\
                                           sudo swapoff -a && sudo swapon -a ;\
                                           sudo swapon {swapfile}'")
	else:
        for server_config in server_configs:
            ip = server_config["privateip"]
			ssh -i ~/.ssh/id_rsa @(ip) "sudo sh -c 'sudo sysctl vm.swappiness=0 ; sudo swapoff -a && swapon -a'"


def cleanup(server_configs, swap):
    for server_config in server_configs:
        ip = server_config["privateip"]
        partition = server_config["partition"]
        datadir = server_config["datadir"]
        swapfile = server_config["swapfile"]
        process = server_config["process"]

        ssh -i ~/.ssh/id_rsa @(ip) @(f"sudo sh -c 'sudo rm -rf {datadir} ;\
                                       sudo umount {partition} ;\
                                       sudo cgdelete cpu:db cpu:cpulow cpu:cpuhigh blkio:db ; true ;\
                                       sudo /sbin/tc qdisc del dev eth0 root ; true ;\
                                       pkill {process}'")
        if swap:
            ssh -i ~/.ssh/id_rsa @(ip) @(f"sudo sh -c 'sudo swapoff -v {swapfile}'")
