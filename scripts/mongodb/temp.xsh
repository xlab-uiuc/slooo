#!/usr/bin/env xonsh

from utils.general import *

class Mongo:
    def __init__(self, **kwargs):
        self.opt = kwargs.get("opt")

    def lol(self):
        print(self.opt)
        print(self.opt[0][0]["name"])
        print("{}".format(self.opt[0][0]["name"]))
        # echo @(f"{self.opt[0][1]["name"]}")

opt = config_parser("./server_configs.json")
mg = Mongo(opt=opt)
mg.lol()