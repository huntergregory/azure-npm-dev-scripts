#!/bin/bash
numPodsToDelete=10000

set -e
numNamespaces=`kubectl get ns | grep test-ns- | wc -l`
numPodsToDeletePerNamespace=`expr $numPodsToDelete / $numNamespaces`
desiredNumPods=`kubectl get pod -A | grep test-ns- | grep Running | wc -l`

startTime=`date -u`
echo "Randomly deleting $numPodsToDelete pods across $numNamespaces namespaces. Will wait until all $desiredNumPods pods are running again"
for (( i=1; i<=$numNamespaces; i++ )); do
    pods=`kubectl get pod -n test-ns-$i | grep Running | shuf -n $numPodsToDeletePerNamespace | awk '{print $1}'`
    for pod in $pods; do
        kubectl -n test-ns-$i delete pod $pod --grace-period=0 --force
    done
done

## the rest is copied from create-deployments.sh
echo
echo "start time: $startTime"
echo "waiting for $desiredNumPods pods to come up"
while true; do
    numPods=`kubectl get pod -A | grep test-ns- | grep Running | wc -l`
    endTime=`date -u`
    if [[ $numPods == $desiredNumPods ]]; then
        break
    fi
    elapsedTime=$(( $(date -d "$endTime" '+%s') - $(date -d "$startTime" '+%s') ))
    echo "$numPods pods up, want $desiredNumPods. Elapsed time: $(( elapsedTime / 60 )) minutes $(( elapsedTime % 60 )) seconds"
    sleep 15
done
echo
echo "DONE. All $desiredNumPods pods are running"
elapsedTime=$(( $(date -d "$endTime" '+%s') - $(date -d "$startTime" '+%s') ))
echo "Elapsed time: $(( elapsedTime / 60 )) minutes $(( elapsedTime % 60 )) seconds"
echo "start time: $startTime"
echo "end time: $endTime"
