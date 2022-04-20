#!/bin/bash
numPods=10
sleepSeconds=$((60*3))
csvFile=latencies.csv
tmpFile=scrape-temp.txt

echo "logs/ folders. Will fail if it exists"
set -e
mkdir logs
if [ -f $csvFile ]; then
    echo "File $csvFile already exists."
    exit 1
fi

npmPods=`kubectl get pod -n kube-system | grep npm | grep Running | awk '{print $1}' | shuf -n $numPods`
echo "OBSERVING THESE PODS"
echo $npmPods
echo

for pod in $npmPods; do
    echo "capturing log for $pod in background"
    kubectl logs -f $pod -n kube-system > logs/$pod.txt &
done

for pod in $npmPods; do
    echo "installing curl on $pod"
    kubectl exec -n kube-system $pod -- bash -c "apt install -y curl"
done

echo "time,pod,podCreateMedian,podCreateP90,podCreateP99,podCreateCount,podDeleteMedian,podDeleteP90,podDeleteP99,podDeleteCount,policyAddMedian,policyAddP90,policyAddP99,policyAddMedian" > $csvFile
round=1
while true; do
    echo "scraping node metrics"
    for pod in $npmPods; do
        time=`date -u`
        kubectl exec -n kube-system $pod -- bash -c "curl localhost:10091/node-metrics" > $tmpFile
        # greps have a whitespace so we don't match the quantile number
        # xargs trims leading whitespace
        ## pod creates
        podCreateMedian=`cat $tmpFile | grep "npm_controller_pod_exec_time{" | grep "create" | grep 'quantile="0.5"' | grep -o -P " [0-9]+\.[0-9]+" | xargs`
        podCreateP90=`cat $tmpFile | grep "npm_controller_pod_exec_time{" | grep "create" | grep 'quantile="0.9"' | grep -o -P " [0-9]+\.[0-9]+" | xargs`
        podCreateP99=`cat $tmpFile | grep "npm_controller_pod_exec_time{" | grep "create" | grep 'quantile="0.99"' | grep -o -P " [0-9]+\.[0-9]+" | xargs`
        podCreateCount=`cat $tmpFile | grep "npm_controller_pod_exec_time_count{" | grep "create" | grep -o -P "[0-9]+"`
        ## pod deletes
        podDeleteMedian=`cat $tmpFile | grep "npm_controller_pod_exec_time{" | grep "delete" | grep 'quantile="0.5"' | grep -o -P " [0-9]+\.[0-9]+" | xargs`
        podDeleteP90=`cat $tmpFile | grep "npm_controller_pod_exec_time{" | grep "delete" | grep 'quantile="0.9"' | grep -o -P " [0-9]+\.[0-9]+" | xargs`
        podDeleteP99=`cat $tmpFile | grep "npm_controller_pod_exec_time{" | grep "delete" | grep 'quantile="0.99"' | grep -o -P " [0-9]+\.[0-9]+" | xargs`
        podDeleteCount=`cat $tmpFile | grep "npm_controller_pod_exec_time_count{" | grep "delete" | grep -o -P "[0-9]+"`
        ## policy creates
        policyAddMedian=`cat $tmpFile | grep "npm_add_policy_exec_time{" | grep 'quantile="0.5"' | grep -o -P " [0-9]+\.[0-9]+" | xargs`
        policyAddP90=`cat $tmpFile | grep "npm_add_policy_exec_time{" | grep 'quantile="0.9"' | grep -o -P " [0-9]+\.[0-9]+" | xargs`
        policyAddP99=`cat $tmpFile | grep "npm_add_policy_exec_time{" | grep 'quantile="0.99"' | grep -o -P " [0-9]+\.[0-9]+" | xargs`
        policyAddCount=`cat $tmpFile | grep "npm_add_policy_exec_time_count{" | grep -o -P "[0-9]+"`
        echo "time: $time"
        echo "pod: $pod"
        echo "podCreateMedian: $podCreateMedian"
        echo "podCreateP90: $podCreateP90"
        echo "podCreateP99: $podCreateP99"
        echo "podCreateCount: $podCreateCount"
        echo "podDeleteMedian: $podDeleteMedian"
        echo "podDeleteP90: $podDeleteP90"
        echo "podDeleteP99: $podDeleteP99"
        echo "podDeleteCount: $podDeleteCount"
        echo "policyAddMedian: $policyAddMedian"
        echo "policyAddP90: $policyAddP90"
        echo "policyAddP99: $policyAddP99"
        echo "policyAddCount: $policyAddCount"
        echo
        ## write to file
        echo "$time,$pod,$podCreateMedian,$podCreateP90,$podCreateP99,$podCreateCount,$podDeleteMedian,$podDeleteP90,$podDeleteP99,$podDeleteCount,$policyAddMedian,$policyAddP90,$policyAddP99,$policyAddCount" >> $csvFile
    done
    echo "finished scraping node metrics for round $round"
    round=$((round+1))
    sleep $sleepSeconds
done
