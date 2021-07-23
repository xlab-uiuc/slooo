#!/bin/bash

while(true)
do
  sudo taskset -ac 2 dd if=/dev/zero of=/data1/tmp.txt bs=1000 count=1400000 conv=notrunc
done

