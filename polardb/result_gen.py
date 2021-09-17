import sys
import os
import fileinput
import json

def result_gen(result_path, tmp_out, slow_type, expno, p99_9, p99, p50):
    specific = []
    print(tmp_out)
    tmp_out = tmp_out.split()
    for i,line in enumerate(tmp_out):
        if i == 1:
            scaling_factor = line[16:].strip()
        elif i == 3:
            clients = line[19:].strip()
        elif i == 4: 
            threads = line[19:].strip()
        elif i == 7:
            o_latency = line[18: -3].strip()
        elif i == 8:
            o_throughput = line[6: -37].strip()
        elif 10 < i:
            specific.append(line.strip()[0:7].strip())
        else:
            continue

    result = {
        "SYS Setup" : {
            "Clients"   : clients,
            "Threads"   : threads,
            "Slow Type" : slow_type,  
            "Expno"     : expno,
            "Scaling Factor": scaling_factor
        },
        "OVERALL"   : {
            "Throughput": float(o_throughput),
            "Latency"   : float(o_latency),
            "P99.9 Latency": float(p99_9),
            "P99 Latency" : float(p99),
            "P50 Latency" : float(p50)
        },
        "SPECIFIC (Latency)"  : {
            "\\set aid random(1, 100000 * :scale)" : float(specific[0]),
            "\\set bid random(1, 1 * :scale)" : float(specific[1]),
            "\\set tid random(1, 10 * :scale)" : float(specific[2]),
            "\\set delta random(-5000, 5000)" : float(specific[3]),
            "BEGIN;" : float(specific[4]),
            "UPDATE pgbench_accounts SET abalance = abalance + :delta WHERE aid = :aid;" : float(specific[5]),
            "SELECT abalance FROM pgbench_accounts WHERE aid = :aid;" : float(specific[6]),
            "UPDATE pgbench_tellers SET tbalance = tbalance + :delta WHERE tid = :tid;" : float(specific[7]),
            "UPDATE pgbench_branches SET bbalance = bbalance + :delta WHERE bid = :bid;" : float(specific[8]),
            "INSERT INTO pgbench_history (tid, bid, aid, delta, mtime) VALUES (:tid, :bid, :aid, :delta, CURRENT_TIMESTAMP);" : float(specific[9]),
            "END;" : float(specific[10]) 
        }
    }

    result_in_json = json.dumps(result, skipkeys = True, allow_nan = True, indent = 4)

    with open(result_path, 'w') as result:
        result.write(result_in_json)

def result_avg_gen(results_path, iters, expno):
    with open(results_path + "{}_1.txt".format(expno), 'r') as file_input:
        dict_json = json.load(file_input)
    
    
    for i in range(2, iters+1):
        with open(results_path + "{}_{}.txt".format(expno, i), 'r') as file_input:
            dict_json_tmp = json.load(file_input)
            dict_json['OVERALL']['Throughput'] += dict_json_tmp['OVERALL']['Throughput']
            dict_json['OVERALL']['Latency'] += dict_json_tmp['OVERALL']['Latency']
            dict_json['OVERALL']['P99.9 Latency'] += dict_json_tmp['OVERALL']['P99.9 Latency']
            dict_json['OVERALL']['P99 Latency'] += dict_json_tmp['OVERALL']['P99 Latency']
            dict_json['OVERALL']['P50 Latency'] += dict_json_tmp['OVERALL']['P50 Latency']
            for k in dict_json['SPECIFIC (Latency)'].keys():
                dict_json['SPECIFIC (Latency)'][k] += dict_json_tmp['SPECIFIC (Latency)'][k]
    
    dict_json['OVERALL']['Throughput'] /= iters
    dict_json['OVERALL']['Latency'] /= iters
    dict_json['OVERALL']['P99.9 Latency'] /= iters
    dict_json['OVERALL']['P99 Latency'] /= iters
    dict_json['OVERALL']['P50 Latency'] /= iters
    for k in dict_json['SPECIFIC (Latency)'].keys():
        dict_json['SPECIFIC (Latency)'][k] /= iters
    
    result_in_json = json.dumps(dict_json, skipkeys = True, allow_nan = True, indent = 4)
    
    with open(results_path +"{}_".format(expno) + "avg.txt", 'w') as result:
        result.write(result_in_json)
    

# result_med_gen should be called by the main parser (run.xsh)
def result_med_gen(results_path, iters, expno):
    if results_path[-1] != "/":
        results_path += "/"
        
    dict_arr = []
    for i in range(1, iters+1):
        with open(results_path + "{}_{}.txt".format(expno, i), 'r') as file_input:
            dict_json_tmp = json.load(file_input)
            dict_arr.append(dict_json_tmp)
            
            # dict_json['OVERALL']['Throughput'] += dict_json_tmp['OVERALL']['Throughput']
            # dict_json['OVERALL']['Latency'] += dict_json_tmp['OVERALL']['Latency']
            # dict_json['OVERALL']['P99 Latency'] += dict_json_tmp['OVERALL']['P99 Latency']
            # dict_json['OVERALL']['P50 Latency'] += dict_json_tmp['OVERALL']['P50 Latency']
            # for k in dict_json['SPECIFIC (Latency)'].keys():
            #     dict_json['SPECIFIC (Latency)'][k] += dict_json_tmp['SPECIFIC (Latency)'][k]
    dict_json = dict_arr[0]
    for k in dict_json["OVERALL"].keys():
        temp_arr = []
        for i in range(0,iters):
            temp_arr.append(dict_arr[i]["OVERALL"][k])
        temp_arr.sort()
        if int(iters / 2 * 2) == iters:
            dict_json["OVERALL"][k] = (temp_arr[int(iters / 2)] + temp_arr[int(iters / 2 - 1)]) / 2
        else:
            dict_json["OVERALL"][k] = temp_arr[int((iters - 1) / 2)]
    
    for k in dict_json["SPECIFIC (Latency)"].keys():
        temp_arr = []
        for i in range(0,iters):
            temp_arr.append(dict_arr[i]["SPECIFIC (Latency)"][k])
        temp_arr.sort()
        if int(iters / 2 * 2) == iters:
            dict_json["SPECIFIC (Latency)"][k] = (temp_arr[int(iters / 2)] + temp_arr[int(iters / 2 - 1)]) / 2
        else:
            dict_json["SPECIFIC (Latency)"][k] = temp_arr[int((iters - 1) / 2)]
    
    
    result_in_json = json.dumps(dict_json, skipkeys = True, allow_nan = True, indent = 4)
    
    with open(results_path + "{}_".format(expno) + "med.txt", 'w') as result:
        result.write(result_in_json)

