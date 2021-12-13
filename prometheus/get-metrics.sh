#!/bin/bash
## note: could forego using curl and port forward the pod instead
## PARAMETER STUFF
help () {
    echo "Get the NPM Prometheus metrics."
    echo
    echo "Usage:"
    echo "./get-metrics.sh <metric-kind>"
    echo
    echo "<metric-kind>"
    echo "    One of 'cluster' or 'node'. Indicates which kind of metrics should be scraped (i.e. the /cluster-metrics or /node-metrics HTTP endpoint)."
    echo "-s"
    echo "    Skip installation of curl on the pod."
    echo "-h"
    echo "    Print this help message."
}
if [ $# == 0 ]; then
    help
    exit 1
fi
if [[ $1 == "-h" ]]; then
    help
    exit 0
fi
metricKind=$1
if [[ $metricKind != "cluster" && $metricKind != "node" ]]; then
    echo "Error: invalid first argument"
    echo
    help
    exit 1
fi
if [[ $2 == "-s" ]]; then
    shouldInstall=false
else
    shouldInstall=true
fi

## BEGIN SCRIPT
set -e
npmPod=`eval kubectl get pod -A | grep -o -P "azure-npm-[0-9a-z]{5}" -m 1`
echo "observing NPM pod: $npmPod"
execPod () {
    kubectl exec -it -n kube-system $npmPod -- bash -c "$1"
}
if [[ $shouldInstall == true ]]; then
    execPod "apt-get update && apt-get install curl --yes"
fi
execPod "curl http://localhost:10091/$metricKind-metrics"
