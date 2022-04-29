from typing import List
import os
import logging

class Results:
    def __init__(self, path) -> None:
        self.file_path: str = path
        # type: str = "ycsb"   # we parse different results files differently as in the output files are different for different benchmarking tools
        self.exp: str = None      # experiment (slow cpu, mem contention etc.,)
        self.exp_type: str = None # slowness injected in leader or follower
        self.trial: int = 0       # experiment trial
        self.throughput: float = 0.0
        self.latencies: List[float] = [] # need this to plot latencies cdf
        self.avg_latency: float = 0.0
        self.p50: float = 0.0
        self.p95: float = 0.0
        self.p99: float = 0.0

    def _parse_results_file(self): #method to parse the results file and set the above class variables
        pass

class YCSBResults(Results):
    def __init__(self, path) -> None:
        super().__init__(path)
        # parse results
        self._parse_results_file()

    def _parse_results_file(self):
        '''Parse the result file and populate the class fields
        '''
        if os.path.exists(self.file_path) == False:
            logging.error(f'YCSB result file {self.file_path} does not exist, aborting')
        
        with open(self.file_path, 'r') as res:
            for line in res.readlines():
                if line.startswith("UPDATE,"):
                    self.latencies.append(float(line.split(",")[2]))
                elif line.startswith("[OVERALL], Throughput(ops/sec),"):
                    self.throughput = float(line.split(" ")[2])
                elif line.startswith("[UPDATE], p50,"):
                    self.p50 = float(line.split(" ")[2])
                elif line.startswith("[UPDATE], p95,"):
                    self.p95 = float(line.split(" ")[2])
                elif line.startswith("[UPDATE], p99,"):
                    self.p99 = float(line.split(" ")[2])
                elif line.startswith("[UPDATE], Average,"):
                    self.avg_latency = float(line.split(" ")[2])
                else:
                    pass

    

class Plot:
    results: List[Results] = None

    def plot_cdf(self):
        pass

    def plot_throughput_compare(self):
        pass

    def plot_avg_latency_compare(self):
        pass

    def plot_p50_latency_compare(self):
        pass

    def plot_p99_latency_compare(self):
        pass

    def run(self):
        pass