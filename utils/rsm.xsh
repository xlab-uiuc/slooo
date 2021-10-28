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
        self.output_path=opt.output_path
        self.primaryip = None
        self.primaryhost = None
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

    def result_extract(self):
        pass
        # This function should call result_extract
    def result_gen(self, system_name, throughput, p99_9, p99, **kwargs):
        result = {
            "SYS Setup" : {
                "Threads"   : self.threads,
                "Slow Type" : self.exp_type,
                "Expno"     : self.exp,
                "Workload"  : self.workload
            },
            "OVERALL"   : {
                "Throughput": float(throughput),
                "P99.9 Latency": float(p99_9),
                "P99 Latency" : float(p99)
            }
        }
        print(type(kwargs))
        if kwargs:
            result["SPECIFIC (Latency)"] = kwargs
        
        result_in_json = json.dumps(result, skipkeys = True, allow_nan = True, indent = 4)
                           
        output_path = os.path.join(self.output_path, "{}_{}_{}_{}_{}_results".format(system_name, self.exp_type,"swapon" if self.swap else "swapoff", self.ondisk, self.threads))
        output_file_path = os.path.join(output_path, str(self.exp) + "_" + str(self.trial) + ".json")
        mkdir -p @(output_path)
        with open(output_file_path, 'w') as result:
            result.write(result_in_json)
