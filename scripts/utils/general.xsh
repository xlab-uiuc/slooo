#!/usr/bin/env xonsh

import os
import json
from utils.constants import *

# reads the server_config json to a list of dictionaries
def config_parser(path):
    server_configs = []
    servermap = {}
    with open(path) as f:
        servers = json.load(f)
        for server in servers:
            server_configs.append(server)
            servermap[server["name"]] = server
            servermap[server["private_ip"]] = server

    return server_configs,servermap

# starts the servers
def start_servers(server_configs):
    for server_config in server_configs:
        az vm start --resource-group @(RESOURCE_GROUP) --subscription @(SUBSCRIPTION) --name @(server_config["name"])

# stops the servers
def stop_servers(server_configs):
    for server_config in server_configs:
        az vm deallocate --resource-group @(RESOURCE_GROUP) --subscription @(SUBSCRIPTION) --name @(server_config["name"])
