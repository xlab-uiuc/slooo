#!/usr/bin/env xonsh

import json
from utils.general import *
from resources.slowness.slow import slow_inject

with open('./test_conf.json', 'r') as conf_input:
    # do something
    nodes = json.load(conf_input)
    
print(nodes["servers"])

config = nodes['servers'][0] # secondary config
ip = config['privateip'] # secondaryip
cpu = config['cpu']



# Have to manually inspect the actual resource usage before injecting the next kind of slowness

#TODO: Clean the cgroup settings and relevant shit for each injection
cleanup(nodes["servers"])
slow_inject('1', nodes["servers"][0], '')
cleanup(nodes["servers"])


input("press enter to continue to exp 2")

scp resources/slowness/lifeloop @(ip):~/
scp resources/slowness/deadloop @(ip):~/

ssh -i ~/.ssh/id_rsa @(secondaryip) f"sh -c 'nohup taskset -ac {cpu} ./lifeloop > /dev/null 2>&1 &'"
lifelooppid =$(ssh -i ~/.ssh/id_rsa @(secondaryip) f"sh -c 'prgep lifeloop'")
slow_inject('2', config, lifelooppid)
cleanup(nodes["servers"])
