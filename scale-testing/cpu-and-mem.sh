#!/bin/bash
sleepSeconds=65

echo "time,pod,cpu,mem" > cpu-and-mem-pod-results.txt
echo "time,node,cpu,cpuPercent,mem,memPercent" > cpu-and-mem-node-results.txt
while true; do
    currentTime=`date -u`
    echo "running k top pod"
    lines=`kubectl top pod -n kube-system | grep npm | awk '{$1=$1;print}' | tr ' ' ',' | tr -d 'm' | tr -d 'Mi'`
    for line in $lines; do
        echo "$currentTime,$line" >> cpu-and-mem-pod-results.txt
    done

    currentTime=`date -u`
    echo "running k top node"
    lines=`kubectl top node | grep -v NAME | awk '{$1=$1;print}' | tr ' ' ',' | tr -d 'm' | tr -d 'Mi' | tr -d '%'`
    for line in $lines; do
        echo "$currentTime,$line" >> cpu-and-mem-node-results.txt
    done
    echo "sleeping $sleepSeconds seconds"
    sleep $sleepSeconds
done
