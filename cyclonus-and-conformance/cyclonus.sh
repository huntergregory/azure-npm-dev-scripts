#!/bin/bash
## CONSTANTS
localResultsFolderName=../../npm-cyclonus-results
resultsFile=$localResultsFolderName/cyclonus-test.txt
npmLogsFile=$localResultsFolderName/npm-logs.txt

## PARAMETERS
help () {
	echo "This script runs cyclonus."
    echo
    echo "Usage:"
    echo "./cylconus.sh [-i <npm-image> -p <npm-profile-name>] [-s]"
    echo "-i <npm-image>"
    echo "    The NPM image. Must include this or use -s."
    echo "-p <npm-profile-name>"
    echo "    The name of the NPM profile (without the file path or '.yaml'). Must include this or use -s."
    echo "-s"
    echo "    Skip NPM installation/restart. Must include this or use -i and -p."
    echo "-h"
    echo "    Print this help message."
}

if [[ "$#" == 0 ]]; then
    help
    exit 1
fi

shouldDeleteExistingContainer=false
while getopts ":i:p:sh" option; do
    case $option in
        i)
            image=$OPTARG;;
        p)
            profile=$OPTARG;;
        s)
            skipNPMInstall=true;;
        h)
            help
            exit 0;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            exit 1;;
   esac
done

if [[ $skipNPMInstall == false && ( -z $image || -z $profile ) ]]; then
    echo "must skip install/restart or provide an image and profile"
    exit 1
fi

## START SCRIPT
echo "Attempting to cd into azure-npm-dev-scripts/cyclonus-and-conformance/   (this will create an error message if already in that folder)"
cd azure-npm-dev-scripts/cyclonus-and-conformance/

set -e
mkdir -p $localResultsFolderName
set +e

# set up NPM
if [[ $skipNPMInstall == true ]]; then
    echo "Skipping NPM installation/restart"
else
    echo "Deploying NPM"
    set -e
    echo "(re)deploying NPM with profile $profile and image $image"
    kubectl apply -f https://raw.githubusercontent.com/Azure/azure-container-networking/master/npm/azure-npm.yaml
    # swap azure-npm image with desired one
    kubectl set image daemonset/azure-npm -n kube-system azure-npm=$image
    # swap NPM profile with desired one
    profilePath="https://raw.githubusercontent.com/Azure/azure-container-networking/master/npm/profiles/$profile.yaml"
    # profilePath="../npm-profiles-with-pprof/$profile.yaml"
    kubectl apply -f $profilePath
    kubectl rollout restart ds azure-npm -n kube-system
    set +e
    echo "sleeping to allow NPM pods to come back up after boot up"
    sleep 45
fi

npmPod=`eval kubectl get pod -A | grep -o -m 1 -P "azure-npm-[0-9a-z]{5}"`
if [[ -z "$npmPod" ]]; then
    echo "Error: NPM pod not found"
    exit 1
fi
echo "will observe NPM pod: $npmPod"
# print out image version
kubectl get pod -n kube-system $npmPod -o yaml | grep image: -m 1

# set up cyclonus
kubectl create clusterrolebinding cyclonus --clusterrole=cluster-admin --serviceaccount=kube-system:cyclonus
kubectl create sa cyclonus -n kube-system
kubectl create -f https://raw.githubusercontent.com/Azure/azure-container-networking/master/test/cyclonus/install-cyclonus.yaml

sleep 5

kubectl wait --for=condition=ready --timeout=5m pod -n kube-system -l job-name=cyclonus

echo "cyclonus job is ready. Waiting for the job to complete"
kubectl wait --for=condition=completed --timeout=180m pod -n kube-system -l job-name=cyclonus

# grab the job logs
echo "cylconus job is complete. Grabbing logs"
kubectl logs -n kube-system job.batch/cyclonus > "$resultsFile"
kubectl logs -n kube-system $npmPod > "$npmLogsFile"

kubectl delete --ignore-not-found=true clusterrolebinding cyclonus 
kubectl delete --ignore-not-found=true sa cyclonus -n kube-system
kubectl delete --ignore-not-found=true -f https://raw.githubusercontent.com/Azure/azure-container-networking/master/test/cyclonus/install-cyclonus.yaml

# if 'failure' is in the logs, fail; otherwise succeed
cat "$resultsFile" | grep -q "failed"
exitCode=$?
endOfMessage=" for image $image and profile $profile"
if [[ $skipNPMInstall == true ]]; then
    endOfMessage=""
fi
echo
if [ $exitCode -eq 0 ]; then
    echo "CYCLONUS RESULT: failed$endOfMessage"
    exit 1
else
    echo "CYCLONUS RESULT: succeeded$endOfMessage"
    exit 0
fi
