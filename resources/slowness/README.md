# Enabling easy, user-friendly slowness configuration.


## Slowness Configs
- CPU Slow
  1. quota
  2. period
  ### user-friendly configs
  User can specify a **2-digit number** for the max-allowed CPU usage precentage. The program will calculate `quota` accordingly.

- CPU Contention
  ## user-friendly configs
  The input will be in the form of "CPU ratio" where the user will specify two number (1 for the contention program and 1 for the database instance)

- Disk Slow
  1. the device id
  2. allowed rate of IO
  ## user-friendly configs
  The user can specify the limiting i/o rate with an integer in B, KB, MB, etc

- Disk Contention (no need for a change)

- Network Slow
  1. the latency to be added

- Memory Contention (Slow)
  1. memory.limit_in_bytes
## Current Code Struc
