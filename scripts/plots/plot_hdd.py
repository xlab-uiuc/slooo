import seaborn as sns
import matplotlib.pyplot as plt
import pandas as pd
import os
from statistics import mean, median

num = 5
plot = True


noslow = {"tput":[], "p99":[], "p99.9":[], "avg":[]}
exp1 = {"tput":[], "p99":[], "p99.9":[], "avg":[]}
exp2 = {"tput":[], "p99":[], "p99.9":[], "avg":[]}
exp3 = {"tput":[], "p99":[], "p99.9":[], "avg":[]}
exp4 = {"tput":[], "p99":[], "p99.9":[], "avg":[]}
exp5 = {"tput":[], "p99":[], "p99.9":[], "avg":[]}
exp6 = {"tput":[], "p99":[], "p99.9":[], "avg":[]}

exp = {"noslow":noslow, 
    "exp1":exp1, 
    "exp2":exp2,
    "exp3":exp3,
    "exp4":exp4,
    "exp5":exp5,
    "exp6": exp6
    }

noslow_swapoff = "mongodb_noslow_swapoff_hdd_250_results"
follower_swapooff = "mongodb_leader_swapoff_hdd_250_results"
follower_swapon = "mongodb_leader_swapon_hdd_250_results"

# noslow = "noslow"
# slow = "slow"

for dir in ["/home/varshith/uiuc/res/lea13jul/"]:
    for folder in [noslow_swapoff, follower_swapooff, follower_swapon]:
    # for folder in [noslow, slow]:
        for file in os.listdir(os.path.join(dir,folder)):
            if "(" in file or os.path.isdir(os.path.join(dir,folder,file)):
                continue
            if folder == noslow_swapoff:
                exp_no = "noslow"
            else:
                exp_no = file.split("_")[0]

            trial_no = int(file.strip(".txt").split("_")[-1])
            print(exp_no, trial_no)
            with open(os.path.join(dir, folder, file)) as f:
                for line in f.readlines():
                    if "Throughput(ops/sec)" in line:
                        exp[exp_no]["tput"].append(float(line.split(" ")[2]))
                    elif "[UPDATE], 99thPercentileLatency(us)" in line:
                        exp[exp_no]["p99"].append(float(line.split(" ")[2]))
                    elif "[UPDATE], 99.9PercentileLatency(us)" in line:
                        exp[exp_no]["p99.9"].append(float(line.split(" ")[2]))
                    elif "[UPDATE], AverageLatency(us)," in line:
                        exp[exp_no]["avg"].append(float(line.split(" ")[2]))


for e in exp:
    print(e,exp[e])

mn_tput = []
mn_p99 = []

med_tput = []
med_p99 = []



for no in exp:
    tput = exp[no]["tput"]
    p99 = exp[no]["p99"]
    p99_9 = exp[no]["p99.9"]
    avg = exp[no]["avg"]
    print(tput)

    mean_tput = mean(tput)
    mean_p99 = mean(p99)
    median_tput = median(tput)
    median_p99 = median(p99)

    mn_tput.append(mean_tput)
    mn_p99.append(mean_p99)

    med_tput.append(median_tput)
    med_p99.append(median_p99)


    print(f"{no} average throughput {mean(tput)}")
    print(f"{no} median throughput {median(tput)}")
    print(f"{no} average p99 {mean(p99)}")
    print(f"{no} median p99 {median(p99)}")

print(dir)

if plot:
    nn = pd.DataFrame(data={'throughput': ["mean throughput"], 
                            'noslow': [mn_tput[0]], 
                            'cpu slow': [mn_tput[1]],
                            'cpu conten.': [mn_tput[2]],
                            'disk slow': [mn_tput[3]],
                            'disk conten.': [mn_tput[4]],
                            'network slow': [mn_tput[5]],
                            'memory conten.': [mn_tput[6]],})

    nn = pd.melt(nn, id_vars = "throughput")

    # print(dfs1)

    sns.catplot(x = 'throughput', y='value', 
                hue = 'variable',data=nn, 
                kind='bar')

    plt.savefig(os.path.join(dir,"mean_throughput.png"))
    plt.show()

    nn = pd.DataFrame(data={'throughput': ["median throughput"], 
                            'noslow': [med_tput[0]], 
                            'cpu slow': [med_tput[1]],
                            'cpu conten.': [med_tput[2]],
                            'disk slow': [med_tput[3]],
                            'disk conten.': [med_tput[4]],
                            'network slow': [med_tput[5]],
                            'memory conten.': [med_tput[6]],})

    nn = pd.melt(nn, id_vars = "throughput")

    # print(dfs1)

    sns.catplot(x = 'throughput', y='value', 
                hue = 'variable',data=nn, 
                kind='bar')

    plt.savefig(os.path.join(dir,"median_throughput.png"))
    plt.show()

    nn = pd.DataFrame(data={'p99': ["mean p99"], 
                            'noslow': [mn_p99[0]], 
                            'cpu slow': [mn_p99[1]],
                            'cpu conten.': [mn_p99[2]],
                            'disk slow': [mn_p99[3]],
                            'disk conten.': [mn_p99[4]],
                            'network slow': [mn_p99[5]],
                            'memory conten.': [mn_p99[6]],})

    nn = pd.melt(nn, id_vars = "p99")

    # print(dfs1)

    sns.catplot(x = 'p99', y='value', 
                hue = 'variable',data=nn, 
                kind='bar')

    plt.savefig(os.path.join(dir,"mean_p99.png"))
    plt.show()

    nn = pd.DataFrame(data={'p99': ["median p99"], 
                            'noslow': [med_p99[0]], 
                            'cpu slow': [med_p99[1]],
                            'cpu conten.': [med_p99[2]],
                            'disk slow': [med_p99[3]],
                            'disk conten.': [med_p99[4]],
                            'network slow': [med_p99[5]],
                            'memory conten.': [med_p99[6]],})

    nn = pd.melt(nn, id_vars = "p99")

    # print(dfs1)

    sns.catplot(x = 'p99', y='value', 
                hue = 'variable',data=nn, 
                kind='bar')

    plt.savefig(os.path.join(dir,"median_p99.png"))
    plt.show()

normalise = True

if normalise:
    nn = pd.DataFrame(data={'throughput': ["mean throughput"], 
                            'noslow': [mn_tput[0]/mn_tput[0]], 
                            'cpu slow': [mn_tput[1]/mn_tput[0]],
                            'cpu conten.': [mn_tput[2]/mn_tput[0]],
                            'disk slow': [mn_tput[3]/mn_tput[0]],
                            'disk conten.': [mn_tput[4]/mn_tput[0]],
                            'network slow': [mn_tput[5]/mn_tput[0]],
                            'memory conten.': [mn_tput[6]/mn_tput[0]],})

    nn = pd.melt(nn, id_vars = "throughput")

    # print(dfs1)

    sns.catplot(x = 'throughput', y='value', 
                hue = 'variable',data=nn, 
                kind='bar')

    plt.savefig(os.path.join(dir,"mean_throughput_norm.png"))
    plt.show()

    nn = pd.DataFrame(data={'throughput': ["median throughput"], 
                            'noslow': [med_tput[0]/med_tput[0]], 
                            'cpu slow': [med_tput[1]/med_tput[0]],
                            'cpu conten.': [med_tput[2]/med_tput[0]],
                            'disk slow': [med_tput[3]/med_tput[0]],
                            'disk conten.': [med_tput[4]/med_tput[0]],
                            'network slow': [med_tput[5]/med_tput[0]],
                            'memory conten.': [med_tput[6]/med_tput[0]],})

    nn = pd.melt(nn, id_vars = "throughput")

    # print(dfs1)

    sns.catplot(x = 'throughput', y='value', 
                hue = 'variable',data=nn, 
                kind='bar')

    plt.savefig(os.path.join(dir,"median_throughput_norm.png"))
    plt.show()

    nn = pd.DataFrame(data={'p99': ["mean p99"], 
                            'noslow': [mn_p99[0]/mn_p99[0]], 
                            'cpu slow': [mn_p99[1]/mn_p99[0]],
                            'cpu conten.': [mn_p99[2]/mn_p99[0]],
                            'disk slow': [mn_p99[3]/mn_p99[0]],
                            'disk conten.': [mn_p99[4]/mn_p99[0]],
                            'network slow': [mn_p99[5]/mn_p99[0]],
                            'memory conten.': [mn_p99[6]/mn_p99[0]],})

    nn = pd.melt(nn, id_vars = "p99")

    # print(dfs1)

    sns.catplot(x = 'p99', y='value', 
                hue = 'variable',data=nn, 
                kind='bar')

    plt.savefig(os.path.join(dir,"mean_p99_norm.png"))
    plt.show()

    nn = pd.DataFrame(data={'p99': ["median p99"], 
                            'noslow': [med_p99[0]/med_p99[0]], 
                            'cpu slow': [med_p99[1]/med_p99[0]],
                            'cpu conten.': [med_p99[2]/med_p99[0]],
                            'disk slow': [med_p99[3]/med_p99[0]],
                            'disk conten.': [med_p99[4]/med_p99[0]],
                            'network slow': [med_p99[5]/med_p99[0]],
                            'memory conten.': [med_p99[6]/med_p99[0]],})

    nn = pd.melt(nn, id_vars = "p99")

    # print(dfs1)

    sns.catplot(x = 'p99', y='value', 
                hue = 'variable',data=nn, 
                kind='bar')

    plt.savefig(os.path.join(dir,"median_p99_norm.png"))
    plt.show()

# num = 5
# dir = "/home/varshith/uiuc/res"
# tp_ns = []
# n_ns = []
# nn_ns = []
# avg_ns=[]
# #noslow
# print(os.path.join(dir,"noslow"))
# for trail in range(1,num+1):
#     with open(os.path.join(dir,"noslow", f"exp1_trial_{trail}.txt")) as f:
#         for line in f.readlines():
#             line = line.strip()
#             if "Throughput(ops/sec)" in line:
#                 tp_ns.append(float(line.split(" ")[2]))
#             elif "[UPDATE], 99thPercentileLatency(us)" in line:
#                 n_ns.append(float(line.split(" ")[2]))
#             elif "[UPDATE], 99.9PercentileLatency(us)" in line:
#                 nn_ns.append(float(line.split(" ")[2]))
#             elif "[UPDATE], AverageLatency(us)," in line:
#                 avg_ns.append(float(line.split(" ")[2]))

# tp_f = []
# n_f = []
# nn_f = []
# avg_f=[]
# #noslow
# for trail in range(1,num+1):
#     with open(os.path.join(dir,"follower", f"exp1_trial_{trail}.txt")) as f:
#         for line in f.readlines():
#             line = line.strip()
#             if "Throughput(ops/sec)" in line:
#                 tp_f.append(float(line.split(" ")[2]))
#             elif "[UPDATE], 99thPercentileLatency(us)" in line:
#                 n_f.append(float(line.split(" ")[2]))
#             elif "[UPDATE], 99.9PercentileLatency(us)" in line:
#                 nn_f.append(float(line.split(" ")[2]))
#             elif "[UPDATE], AverageLatency(us)," in line:
#                 avg_f.append(float(line.split(" ")[2]))

# print(tp_ns,tp_f)
# tput = pd.DataFrame(data={'through_put': [f"trial{x}" for x in range(1,num+1)], 
#                          'noslow': tp_ns, 
#                          'follower_slow': tp_f})

# tput = pd.melt(tput, id_vars = "through_put")

# # print(dfs1)

# sns.catplot(x = 'through_put', y='value', 
#             hue = 'variable',data=tput, 
#             kind='bar')

# plt.savefig(os.path.join(dir,"tput.png"))
# plt.show()
# print(avg_ns,avg_f)
# nn = pd.DataFrame(data={'avg_latency': [f"trial{x}" for x in range(1,num+1)], 
#                          'noslow': avg_ns, 
#                          'follower_slow': avg_f})

# nn = pd.melt(nn, id_vars = "avg_latency")

# # print(dfs1)

# sns.catplot(x = 'avg_latency', y='value', 
#             hue = 'variable',data=nn, 
#             kind='bar')

# plt.savefig(os.path.join(dir,"avglat.png"))
# plt.show()
# print(n_ns,n_f)
# nn = pd.DataFrame(data={'p99_latency': [f"trial{x}" for x in range(1,num+1)], 
#                          'noslow': n_ns, 
#                          'follower_slow': n_f})

# nn = pd.melt(nn, id_vars = "p99_latency")

# # print(dfs1)

# sns.catplot(x = 'p99_latency', y='value', 
#             hue = 'variable',data=nn, 
#             kind='bar')

# plt.savefig(os.path.join(dir,"p99.png"))
# plt.show()
# print(nn_ns,nn_f)
# nnn = pd.DataFrame(data={'p99.9_latency': [f"trial{x}" for x in range(1,num+1)], 
#                          'noslow': nn_ns, 
#                          'follower_slow': nn_f})

# nnn = pd.melt(nnn, id_vars = "p99.9_latency")

# # print(dfs1)

# sns.catplot(x = 'p99.9_latency', y='value', 
#             hue = 'variable',data=nnn, 
#             kind='bar')

# plt.savefig(os.path.join(dir,"p99.9.png"))
# plt.show()

# # data = [[288.015599220039, 338.98389822317176, 386.387120429319],
# # [291.195018865912, 320.68528764749016, 420.6929884501925]]