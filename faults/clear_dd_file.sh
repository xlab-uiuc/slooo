#!/bin/bash

bs=$1
data_dir=$2
temp_file="${data_dir}/temp.txt"

while(true)
do
  dd if=/dev/zero of="$temp_file" bs="$bs" count=1400000 conv=notrunc
done