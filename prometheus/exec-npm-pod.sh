#!/bin/bash
set -e
npmPod=`eval kubectl get pod -A | grep -o -P "azure-npm-[0-9a-z]{5}" -m 1`
echo "entering NPM pod: $npmPod"
kubectl exec -it -n kube-system $npmPod -- bash
