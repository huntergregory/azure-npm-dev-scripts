#!/bin/bash
numNamespaces=5

set -e
numDeployments=`ls deployments/ | wc -l`
desiredNumPods=$(( numDeployments * numNamespaces ))

startTime=`date -u`
summary="$desiredNumPods deployments. $numDeployments deployments in $numNamespaces namespaces"
echo "creating $summary"
for (( i=1; i<=$numNamespaces; i++ )); do
    kubectl create ns test-ns-$i
    kubectl apply -n test-ns-$i -f deployments/
done

echo
echo "start time: $startTime"
echo "created $summary"
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
