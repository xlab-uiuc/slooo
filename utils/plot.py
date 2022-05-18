from typing import List
import os
import logging
import pandas as pd
import seaborn as sns
import matplotlib.pyplot as plt


# The result types can be read from the file_path
class Result:
    def __init__(self, file_path, exp, exp_type, trial) -> None:
        self.file_path: str = file_path
        self.exp: str = exp  # experiment (slow cpu, mem contention etc.,)
        self.exp_type: str = exp_type  # slowness injected in leader or follower
        self.trial: int = trial  # experiment trial
        self.throughput: float = 0.0
        self.latencies: List[float] = []  # need this to plot latencies cdf
        self.avg_latency: float = 0.0
        self.p50: float = 0.0
        self.p95: float = 0.0
        self.p99: float = 0.0
        self._parse_result_file()

    def _parse_result_file(self):  # method to parse the results file and set the above class variables
        pass


class YCSBResult(Result):
    def _parse_result_file(self):
        """
        Parse the result file and populate the class fields
        """
        if not os.path.exists(self.file_path):
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


"""
This class is used to group all results from the same trial and retrieves the median of each metric
"""


class Results(object):
    # TODO: how can I draw the median results using seaborn and pandas?
    def __init__(self, results: List[Result]):
        self.results = results
        self.exp = results[0].exp
        self.exp_type = results[0].exp_type

        throughputs_arr = [res.throughput for res in self.results]
        p50_arr = sorted([res.p50 for res in self.results])
        p95_arr = sorted([res.p95 for res in self.results])
        p99_arr = sorted([res.p99 for res in self.results])
        avg_arr = sorted([res.avg_latency for res in self.results])

        # TODO: populate this latencies list entry
        self.latencies: List[float] = []
        self.throughput_median = throughputs_arr[int((len(self.results) - 1) / 2 + 1)]
        self.latency_p50_median = p50_arr[int((len(self.results) - 1) / 2 + 1)]
        self.latency_p95_median = p95_arr[int((len(self.results) - 1) / 2 + 1)]
        self.latency_p99_median = p99_arr[int((len(self.results) - 1) / 2 + 1)]
        self.latency_avg_median = avg_arr[int((len(self.results) - 1) / 2 + 1)]

    def __dict__(self):
        result_dict = {
            "Experiment": self.exp + self.exp_type,
            "Throughput": self.throughput_median,
            "Latency P50": self.latency_p50_median,
            "Latency P95": self.latency_p95_median,
            "Latency P99": self.latency_p99_median,
            "Latency Avg": self.latency_avg_median
        }
        return result_dict

    def to_pd_DataFrame(self):
        return pd.DataFrame(self.__dict__(), index=list(range(len(self.__dict__().keys()))))


"""
Pass in results of interest when initiating a Plot instance to draw comparative figures 
"""


class Plot:
    def __init__(self, results: List[Results]):
        self.results = results
        self.results_pd = pd.DataFrame()

        # construct a Pandas DataFrame object here
        for res in results:
            if self.results_pd.empty:
                self.results_pd = res.to_pd_DataFrame()
            else:
                self.results_pd = pd.concat([self.results_pd, res.to_pd_DataFrame()], ignore_index=True)

    def cdf(self):
        """
        not sure which result should be used
        """
        cdf_pd = pd.DataFrame()
        for result in self.results:
            experiment = result.exp + result.exp_type
            # construct a DataFrame object for plotting
            if cdf_pd.empty:
                cdf_pd = pd.DataFrame({"Latency": result.latencies, "Experiment": [experiment] * len(result.latencies)})            
            else:
                cdf_pd = pd.concat([cdf_pd, \
                    pd.DataFrame({"Latency": result.latencies, "Experiment": [experiment] * len(result.latencies)})], ignore_index=True)

        sns.displot(data = cdf_pd, x="Latency", hue="Experiment", kind="ecdf")
        plt.savefig("")

    def throughput_compare(self):
        sns.catplot(data = self.results_pd, x="Experiment", y="Throughput", hue="Experiment")
        plt.savefig("")

    def avg_latency_compare(self):
        sns.catplot(data = self.results_pd, x="Experiment", y="Latency Avg", hue="Experiment")
        plt.savefig("")

    def p50_latency_compare(self):
        sns.catplot(data = self.results_pd, x="Experiment", y="Latency P50", hue="Experiment")
        plt.savefig("")

    def p95_latency_compare(self):
        sns.catplot(data = self.results_pd, x="Experiment", y="Latency P95", hue="Experiment")
        plt.savefig("")

    def p99_latency_compare(self):
        sns.catplot(data = self.results_pd, x="Experiment", y="Latency P99", hue="Experiment")
        plt.savefig("")
