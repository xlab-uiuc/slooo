from utils.general import *

class RSM:
    def __init__(self, **kwargs):
        opt = kwargs.get("opt")
        self.ondisk = opt.ondisk
        nodes = config_parser(opt.server_configs)
        self.server_configs = nodes["servers"]
        self.client_configs = nodes["client"]
        self.workload = opt.workload
        self.threads = opt.threads
        self.runtime = opt.runtime
        self.exp = kwargs.get("exp")
        self.swap = True if self.exp == "6" else False
        self.exp_type = "noslow" if self.exp == "noslow" else opt.exp_type
        self.trial = kwargs.get("trial")
        self.primaryip = None
        self.primaryport = None
        self.slowdownip = None
        self.slowdownpid = None

    def server_setup(self):
        init_disk(self.server_configs, self.exp)
        set_swap_config(self.server_configs, self.swap)

    def start_db(self):
        pass

    def db_init(self):
        pass

    def ycsb_load(self):
        pass

    def ycsb_run(self):
        pass

    def db_cleanup(self):
        pass

    def server_cleanup(self):
        cleanup(self.server_configs, self.swap)

    def run(self):
        pass