#!/usr/bin/env xonsh
import json
import argparse
def parse_opt():
    parser = argparse.ArgumentParser()
    parser.add_argument("--file_path", type=str, help="location (include the file name) where the config file will be stored")
    parser.add_argument("--cpu_slow_percentage", type=float, default=0.05, help="the percentage of CPU resource an instance allowed to use")
    parser.add_argument("--cpu_contention_ratio", type=float, default=64, help="CPU share ratio between the contention program and the instance (Contention Program share / Instance share)")
    parser.add_argument("--disk_slow_bps", type=str, default="524288", help="the bps limit to the rate of writing and reading from disk")
    parser.add_argument("--network_slow_latency", type=int, default=400, help="latency (in ms) to be added to the instance's network adapter")
    parser.add_argument("--memory_contention_mem_limit_in_bytes", type=str, default="47088768", help="allowed amount of memory resource (in bytes) that can be allocated")
    opt = parser.parse_args()
    return opt

def main(opt):
    file_path = opt.file_path     
    opt_dict = opt.__dict__
    opt_dict.pop("file_path")
    
    opt_json = json.dumps(opt_dict, sort_keys=True, indent=4, separators=(',', ': '))
    print(opt_json)
    with open(file_path, 'w') as f:
        f.write(opt_json)

if __name__ == "__main__":
    opt = parse_opt()
    main(opt)
