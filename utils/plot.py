from typing import List


class Results:
    file_path: str = None
    type: str = "ycsb"   # we parse different results files differently as in the output files are different for different benchmarking tools
    exp: str = None      # experiment (slow cpu, mem contention etc.,)
    exp_type: str = None # slowness injected in leader or follower
    trial: int = 0       # experiment trial
    throughput: float = 0.0
    latencies: List[float] = None # need this to plot latencies cdf
    avg_latency: float = 0.0
    p50: float = 0.0
    p95: float = 0.0
    p99: float = 0.0

    def parse_results_file(self): #method to parse the results file and set the above class variables
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