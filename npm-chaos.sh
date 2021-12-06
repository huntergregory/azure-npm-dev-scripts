#!/bin/bash
## CONSTANTS
start=1
numOfNs=50
numofLabels=100
numofLoopForLabels=1
numDeleteLoops=2

podFileName=pods_in_ns.txt
policyFileName=netpols_in_ns.txt
logFileName="npm.log"
cleanupBeforeStarting=true
runCPUCaptureInBackground=true

## arrays
namespaces=(web0)
labelsArray=(chaos=true)

## PARAMETERS
help () {
    echo "This script creates resources and can capture pprof for cpu or memory."
    echo "The script can create namespaces, deployments, and network policies, and label the deployments."
    echo "It can be as chaotic as you want based on global constants in the script."
    echo
    echo "Usage:"
    echo "./npm-chaos.sh -i <npm-image> -p <npm-profile-name> [-n <experiment-name] [-a <action>] [-s] [-m|-c] [-x]"
    echo "-h"
    echo "    Print this help message."
    echo "-i <npm-image>"
    echo "    The NPM image."
    echo "-p <npm-profile-name>"
    echo "    The name of the NPM profile (without the file path or '.yaml')."
    echo "-a <action>"
    echo "    Specify an action. Can be one of 'deleteallpolicies', 'deletens', 'exitbeforenetpol', or 'exitbeforedeletes'. Default is 'none'."
    echo "-s"
    echo "    Save the NPM log after finishing. Will restart the daemonset to get a fresh log."
    echo "-m"
    echo "    Capture pprof memory. Can specify at most one of -m or -c."
    echo "-c"
    echo "    Capture pprof cpu. Can specify at most one of -m or -c."
    echo "-n <experiment-name>"
    echo "    Specify an experiment name. Default is 'experiment'."
    echo "-x"
    echo "    Don't sleep."
}

if [[ "$#" == 0 ]]; then
    help
    exit 1
fi
while getopts ":i:p:n:a:smcxh" option; do
    case $option in
        i)
            image=$OPTARG;;
        p)
            profile=$OPTARG;;
        a)
            action=$OPTARG;;
        s)
            shouldSaveLog=true;;
        m)
            if [[ $haveCaptureMode == "true" ]]; then
                echo "You can only specify one capture mode."
                exit 1
            fi
            haveCaptureMode=true
            captureMode="memory";;
        c)
            if [[ $haveCaptureMode == "true" ]]; then
                echo "You can only specify one capture mode."
                exit 1
            fi
            haveCaptureMode=true
            captureMode="cpu";;
        n)
            experimentName=$OPTARG;;
        x)
            shouldSleep=false;;
        h) # help
            help
            exit 0;;
        \?) # Invalid option
            echo "Error: Given an invalid option"
	    echo "used args: $@"
            exit;;
   esac
done

if [[ -z "$image" ]]; then
    echo "Error: No image specified. Use -h for extra info."
    exit 1
fi
if [[ -z "$profile" ]]; then
    echo "Error: No profile specified. Use -h for extra info."
    exit 1
fi

if [[ -z "$experimentName" ]]; then
    experimentName="experiment"
fi
if [[ -z "$captureMode" ]]; then
    captureMode="none"
else
    if [[ -z "$action" ]]; then
	action="none" # TODO set default action here if desired
    fi
fi
if [[ $shouldSaveLog != "true" ]]; then
    shouldSaveLog=false
fi
if [[ $shouldSleep != "false" ]]; then
    shouldSleep=true
fi
if [[ -z "$action" ]]; then
    action="none"
fi

profilePath="npm-profiles-with-pprof/$profile.yaml"

podResultsFolderName="/npm-chaos-results/$experimentName/$captureMode"
localResultsFolderName="../npm-chaos-results/$experimentName/$captureMode"

## when using docker exec ... npm-chaos.sh, the execution will start at the root folder (/), so we need to move into the repo
echo "Original working directory:"
pwd
echo "Attempting to cd into azure-npm-dev-scripts/   (this will create an error message if already in that folder)"
cd azure-npm-dev-scripts/
echo "Working directory after cd:"
pwd

## display and write config to file
set -x
set -e
mkdir -p $localResultsFolderName
set +e
set +x
cat > $localResultsFolderName/chaos-parameters.txt << EOF
Running NPM Chaos with the following config:
image: $image
profile: $profilePath
capture mode: $captureMode
experiment name: $experimentName
action: $action
save log: $shouldSaveLog
sleep: $shouldSleep

Using the following constants:
namespaces: $numOfNs
labels: $numofLabels
label loops: $numofLoopForLabels
delete loops: $numDeleteLoops
cleanup before starting: $cleanupBeforeStarting
run CPU capture in background: $runCPUCaptureInBackground

EOF

cat $localResultsFolderName/chaos-parameters.txt

## FUNCTIONS
generateNs () {
    for (( i=$start; i<=$numOfNs; i++ ))
    do
        #sufix=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 5 | head -n 1)
        sufix=test
        namespaces=("${namespaces[@]}" "web-$sufix-$i")
    done
}

generateLabels () {
    labelsArray=(chaos=true)
    for (( i=$start; i<=$numofLabels; i++ ))
    do
        labelKey=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 5 | head -n 1)
        labelVal=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 5 | head -n 1)
        labelsArray=("${labelsArray[@]}" "chaos-$labelKey=$labelVal")
    done
}

labelAllPodsInNs () {    
    generateLabels
    kubectl label pods -n $1 --overwrite --all ${labelsArray[@]}
}

deleteRandomPodsNs () {
    echo "Deleting random pods in namespace $1"
    #list all pods in the namespace into a file
    kubectl get pods -n $1 | grep -v "NAME" | awk '{print $1}' > pods_in_ns.txt

    #get 10 random pods and delete them
    podname=$(shuf -n 10 pods_in_ns.txt | xargs)
    kubectl delete pod -n $1 $podname
}

deleteRandomPoliciesNs () {    
    echo "Deleting random Network Policies in namespace $1"
    #list all pods in the namespace into a file
    kubectl get netpol -n $1 | grep -v "NAME" | awk '{print $1}' > netpols_in_ns.txt

    #get 10 random netpols and delete them
    polname=$(shuf -n 10 netpols_in_ns.txt | xargs)
    kubectl delete netpol -n $1 $polname
}

deleteAllNetpols () {
    for ns in ${namespaces[@]}; do
        kubectl get netpol -n $ns | grep -v "NAME" | awk '{print $1}' > netpols_in_ns.txt

        #get 10 random netpols and delete them
        polname=$(cat netpols_in_ns.txt | xargs)
        kubectl delete netpol -n $ns $polname
    done
}

cleanUpAllResources () {    
    #delete old pod deployments
    echo "Cleaning up any preexisting resources"
    rm podDeployments/deployment*.yml
    rm $podFileName
    rm $policyFileName
    echo "Deleting all created namespaces"
    kubectl delete ns ${namespaces[@]} --ignore-not-found=true
    kubectl delete ns test1replace --ignore-not-found=true
}

conditionalSleep () {
    if [[ $shouldSleep == "true" ]]; then
        sleep $1
    fi
}

## BEGIN SCRIPT
set -x
if [[ $cleanupBeforeStarting == "true" ]]; then
    cleanUpAllResources
fi

# deploy NPM
echo "(re)deploying NPM with profile $profile and image $image"
kubectl apply -f https://raw.githubusercontent.com/Azure/azure-container-networking/master/npm/azure-npm.yaml
# swap azure-npm image with desired one
kubectl set image daemonset/azure-npm -n kube-system azure-npm=$image
# swap NPM profile with desired one
kubectl apply -f $profilePath
kubectl rollout restart ds azure-npm -n kube-system
kubectl describe daemonset azure-npm -n kube-system
echo "sleeping to allow NPM pods to come back up after boot up"
sleep 60

echo "pods to start:"
kubectl get pods -A
echo

echo "netpols to start:"
kubectl get netpol -A
echo

npmPod=`eval kubectl get pod -A | grep -o "azure-npm-[0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z]" -m 1`
if [[ -z "$npmPod" ]]; then
    echo "Error: NPM pod not found"
    exit 1
fi
echo "will observe NPM pod: $npmPod"
# print out image version
kubectl get pod -n kube-system $npmPod -o yaml | grep image: -m 1

saveArtifactsAndExit () {
    if [[ $shouldSaveLog == "true" ]]; then
        logFilePath="$localResultsFolderName/$logFileName"
        echo "Saving npm logs to $logFilePath"
        echo "sleeping in case npm is still writing to logs"
        conditionalSleep 60 # a minute might be overkill
        kubectl logs -n kube-system $npmPod > $logFilePath
    fi
    if [[ $captureMode != "none" ]]; then
        echo "Saving pprof results"
        kubectl cp -n kube-system $npmPod:$podResultsFolderName/ $localResultsFolderName/
    fi
    echo "waiting for any captures to finish (only necessary if cpu captures are happening in the background)"
    wait
    echo "final capture has finished"
    exit 0
}

execPod () {
    echo "BEGIN COMMAND STDOUT"
    kubectl exec -it $npmPod -n kube-system -- bash -c "$1"
    echo "END COMMAND STDOUT"
}

capture () {
    # first arg is the name for the pprof file
    # second arg is the sleep time before capturing (for memory only)
    podFilePath="$podResultsFolderName/$1.out"
    if [[ $captureMode == "cpu" ]]; then
        echo "getting pprof for cpu: $1"
        commandString="curl localhost:10091/debug/pprof/profile -o $podFilePath"
        if [[ $runCPUCaptureInBackground == "false" ]]; then
            execPod "$commandString"
        else
            wait # for any previous capture to finish (only would happen if the number of namesaces etc. is low)
            # pprof profile looks at CPU usage over 30 seconds, so we want to record while NPM calculations are happening
            # the & makes the command run in the background
            execPod "$commandString" &
        fi
    fi
    if [[ $captureMode == "memory" ]]; then
        conditionalSleep $2
        echo "CURRENT MEMORY: $1"
        k top -n kube-system $npmPod
        echo "getting pprof for heap: $1"
        execPod "curl localhost:10091/debug/pprof/heap -o $podFilePath"
    fi
}

if [[ $captureMode != "none" ]]; then
    echo "setting up npm pod environement for capturing"
    execPod "mkdir -p $podResultsFolderName && apt update && apt-get install curl --yes"
fi

if [[ $captureMode == "cpu" ]]; then
    capture "dormant" 0
    echo "waiting for 'dormant' cpu capture to run"
    wait
    echo "'dormant' capture has finished"
fi

capture "initial" 0

echo "Generating $numOfNs namespaces"
generateNs
echo "Done Generating NS"

echo ${namespaces[@]}


if [[ "$action" = "deleteallpolicies" ]]; then
    deleteAllNetpols
    capture "after-deleting-all-netpols" 90
    saveArtifactsAndExit
fi

if [[ "$action" = "deletens" ]]; then
    cleanUpAllResources
    capture "after-deleting-all-resources" 90
    saveArtifactsAndExit
fi


kubectl create ns test1replace
#delete old pod deployments
rm podDeployments/deployment*.yml
for i in ${namespaces[@]}; do
    kubectl create ns $i
    sed "s/test1replace/$i/g" podDeployments/nginx_deployment.yaml > podDeployments/deployment-$i.yml
done
capture "after-creating-namespaces" 90

# Apply all pod deployments
kubectl apply -f podDeployments/
capture "after-creating-deployments" 90

#Now apply labels to the deployment
for ns in ${namespaces[@]}; do
    echo "Applying Labels to $ns"
    for (( i=$start; i<=$numofLoopForLabels; i++ ))
    do               
        labelAllPodsInNs $ns
    done
done
capture "after-labeling-deployments" 90

#######################
if [[ "$action" = "exitbeforenetpol" ]]; then
    saveArtifactsAndExit
fi
#######################

for ns in ${namespaces[@]}; do
    kubectl apply -n $ns -f networkPolicies/ 
done
capture "after-creating-netpols" 90

if [[ "$action" = "exitbeforedeletes" ]]; then
    saveArtifactsAndExit
fi

echo "#####################Deleting random pods and policies#############################"
for i in $(seq 1 $numDeleteLoops);do
    echo "/////////////////Welcome $i times/////////////////"

    for ns in ${namespaces[@]}; do
        echo "Deleting random pods in namespace $ns"
        #list and delete random pods in the namespace
        deleteRandomPodsNs $ns
        conditionalSleep 3
        #Re-add labels to new pods
        labelAllPodsInNs $ns
        conditionalSleep 2        
        #list and delete random netpols in the namespace
        deleteRandomPoliciesNs $ns
        conditionalSleep 2
    done
    
    conditionalSleep 5
done

capture "after-deleting-labels" 90

# Cleaning up all resources
cleanUpAllResources
capture "after-deleting-all-resources" 90
saveArtifactsAndExit

