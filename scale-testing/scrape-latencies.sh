#!/bin/bash
numPods=10
sleepSeconds=$((60*3))

echo "creating latencies/ and logs/ folders. Will fail if these exist"
set -e
mkdir latencies
mkdir logs

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

round=1
while true; do
    echo "scraping node metrics"
    for pod in $npmPods; do
        fileName="latencies/$pod-round-$round.txt"
        echo `date -u` > $fileName
        kubectl exec -n kube-system $pod -- bash -c "curl localhost:10091/node-metrics" >> $fileName
    done
    round=$(( round + 1 ))
    sleep $sleepSeconds
done
