    # plot.py provides functions to draw related figs from data files in json format
import matplotlib.pyplot as plt
import numpy as np
import os,sys,json
    
    # Read all files and generate the figure
    # In the one big figure, 6 subgraphs are contained. 
    # Each subgraph has four column: leader, follower, learner and noslow

# TODO Write this function into a really generic one
# 1. the function takes a variable-length input
# 2. the input should be a comma-separated string (or an array?). An item in the input should be an item in the json file, use '^' as separation to indicate the hierarchical information to locate the item
# 3. on encountering an recognized item, skip the item and try next one. After all figures are generated, print out the figure that could not be generated
# 4. slowness_config and time should be included in the generated file name

# Specific TODOs
# TODO 1: remove all preset data items from the file
# TODO 2: add what?

# param1: the father folder to all slowness types
# param2: specific items to be generated
# param3:  
def figure_gen(**kwargs)

    if len(sys.argv) != 5:
        print("Incorrect number of inputs!")
        print("> Param 1: (logged / unlogged) if the data was logged")
        print("> Param 2: number of clients")
        print("> Param 3: number of threads")
        print("> Param 4: (tps/latency_avg/latency_P99/latency_P50) type of figure")
        exit()
    if_logged = str(sys.argv[1])
    clients = str(sys.argv[2])
    threads = str(sys.argv[3])
    data_type = str(sys.argv[4])
    
    # Read all the files into the dict array
    dict_arr = []
    
    with open("results/"+ clients + "_" + threads + "/polardb_noslow_" + if_logged + "_32_"  + clients + "_" + threads + "_results/exp1_trial_med", 'r') as file_input:
        dict_arr.append(json.load(file_input))
    
    name_arr = ["leader", "follower", "learner"]
    for i in name_arr:
        for k in range(1,7):
            with open("results/"+ clients + "_" + threads + "/polardb_" + str(i) + "_" + if_logged + "_32_" + clients + "_" + threads + "_results/exp" + str(k) + "_trial_med", 'r') as file_input:
                dict_arr.append(json.load(file_input))
    
    # Generate the figure W.R.T the data wanted
    size = 6
    x = np.arange(size)
    total_width, n = 0.8, 4
    width = total_width / n
    x = x - (total_width - width) / 2
    
    noslow_data = np.ones(size)
    leader_data = np.ones(size)
    follower_data = np.ones(size)
    learner_data = np.ones(size)
    
    if data_type == "tps":
        key_1 = "Throughput"
    elif data_type == "latency_avg": 
        key_1 = "Latency"
    elif data_type == "latency_P99":
        key_1 = "P99 Latency"
    elif data_type == "latency_P50":
        key_1 = "P50 Latency"
    else:
        print("Unsupported Data Type ", data_type)
        exit()
    
    noslow_data *= dict_arr[0]["OVERALL"][key_1]
    
    for i in range(1,7):
        leader_data[i - 1] *= dict_arr[i]["OVERALL"][key_1]
    for i in range(7,13):
        follower_data[i - 7] *= dict_arr[i]["OVERALL"][key_1]
    for i in range(13,19):
        learner_data[i - 13] *= dict_arr[i]["OVERALL"][key_1]
    
    
    plt.bar(1 + x, noslow_data, width=width, label='no-slowness')
    plt.bar(1 + x + width, leader_data, width=width, label='leader') 
    plt.bar(1 + x + 2 * width, follower_data, width=width, label='follower')
    plt.bar(1 + x + 3 * width, learner_data, width=width, label='learner')
    plt.title(data_type)
    plt.legend() 
    plt.show()
    plt.savefig("results/"+ clients + "_" + threads + "/result_" + data_type + ".png")
    
