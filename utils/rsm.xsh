from utils.general import *

class RSM:
    def __init__(self, **kwargs):
        opt = kwargs.get("opt")
        self.ondisk = opt.ondisk
        self.nodes = config_parser(opt.server_configs)
        self.server_configs = self.nodes["servers"]
        self.client_configs = self.nodes["client"]
        self.workload = opt.workload
        self.threads = opt.threads
        self.runtime = opt.runtime
        self.exp = kwargs.get("exp")
        self.swap = True if self.exp == "6" else False
        self.trial = kwargs.get("trial")
        self.output_path=opt.output_path
        self.primaryip = None
        self.primaryhost = None
        self.fault_server_config = None
        self.fault_pids = None

    def server_setup(self):
        init_disk(self.server_configs, self.exp)
        set_swap_config(self.server_configs, self.swap)

    def start_db(self):
        pass

    def db_init(self):
        pass

    def benchmark_load(self):
        pass

    def benchmark_run(self):
        pass

    def db_cleanup(self):
        pass

    def server_cleanup(self):
        cleanup(self.server_configs, self.swap)

    def run(self):
        start_servers(self.server_configs)

        self.server_cleanup()

        self.server_setup()
        self.start_db()
        self.db_init()

        self.benchmark_load()

        fault_inject(self.exp, self.fault_server_config, self.fault_pids)

        self.benchmark_run()

        self.server_cleanup()

        stop_servers(self.server_configs + [self.pd_configs])

    def cleanup(self):
        start_servers(self.server_configs)
        self.server_cleanup()
        stop_servers(self.server_configs)