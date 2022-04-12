#!/bin/bash
numPodsToDelete=10000

set -e
desiredNumPods=`kubectl get pod -A | grep test-ns- | grep Running | wc -l`
numDeployments=`ls deployments/ | wc -l`
numLabelsToDelete=`expr $numPodsToDelete * $numDeployments / $desiredNumPods`
labelfilter="label-1"

startTime=`date -u`
echo "Randomly deleting about $numPodsToDelete pods by deleting $numLabelsToDelete labels. Will wait until all $desiredNumPods pods are running again"
for (( i=2; i<=$numLabelsToDelete; i++ )); do
    labelfilter="${labelfilter}, label-$i"
done

kubectl delete pod -A -l 'app in (labelfilter)' --grace-period=1

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
