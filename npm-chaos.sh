#!/bin/bash
## CONSTANTS
start=1
numOfNs=50 # 15 replicas per namespace
numofLabels=100
numofLoopForLabels=1
numDeleteLoops=2

createDeployments=false
cleanupBeforeStarting=true
podFileName=pods_in_ns.txt
policyFileName=netpols_in_ns.txt
logFileName="npm.log"
runCPUCaptureInBackground=true
runTraceCaptureInBackground=true
traceSeconds=30

## arrays
namespaces=(web0)
labelsArray=(chaos=true)

## PARAMETERS
help () {
    echo "This script creates resources and can capture performance metrics e.g. exec times, cpu, memory, and tracing."
    echo "The script can create namespaces, deployments, and network policies, and label the deployments."
    echo "It can be as chaotic as you want based on global constants in the script."
    echo
    echo "Usage:"
    echo "./npm-chaos.sh {-s}|{-i <npm-image> -p <npm-profile-name> [-n <experiment-name] [-d <delete-action>] [-c <capture-mode>] [-a <capture-area>] [-l] [-x]"
    echo
    echo "Must specify one of -s or both -i and -p."
    echo "Example: to delete all network policies and exit: ./npm-chaos.sh -s -d netpols-and-exit"
    echo
    echo "-s"
    echo "    Skip NPM installation and restart."
    echo "-i <npm-image>"
    echo "    The NPM image."
    echo "-p <npm-profile-name>"
    echo "    The name of the NPM profile (without the file path or '.yaml')."
    echo "-n <experiment-name>"
    echo "    Specify an experiment name. Default is 'experiment'."
    echo "-d <delete-action>"
    echo "    Specify a delete action. Default is 'all-after'. Other options are 'netpols-and-exit', 'ns-and-exit', 'labels-randomly', 'pods-randomly', 'netpols-randomly', or 'none'. 'labels-randomly' is currently unimplemented."
    echo "-l"
    echo "    Save the NPM log after finishing."
    echo "-c <capture-mode"
    echo "    Capture pprof for the specified mode. Can be 'cpu', 'memory', or 'trace'."
    echo "-a <capture-area>"
    echo "    Default is 'all'. Can be set to 'initial', 'after-creating-netpols', etc. to only perform one capture (specifically, the line of code: 'capture \"<capture-area>\"')."
    echo "-x"
    echo "    Don't sleep."
    echo "-h"
    echo "    Print this help message."
}

if [[ "$#" == 0 ]]; then
    help
    exit 1
fi

skipNPMInstall=false
experimentName="experiment"
captureMode="none"
shouldSaveLog=false
shouldSleep=true
deleteAction="all-after"
captureArea="all"
while getopts ":i:p:n:d:c:a:slxh" option; do
    case $option in
        i)
            image=$OPTARG;;
        p)
            profile=$OPTARG;;
        d)
            deleteAction=$OPTARG;;
        s)
            skipNPMInstall=true;;
        l)
            shouldSaveLog=true;;
        c)
            captureMode=$OPTARG;;
        a)
            captureArea=$OPTARG;;
        n)
            experimentName=$OPTARG;;
        x)
            shouldSleep=false;;
        h)
            help
            exit 0;;
        \?) # Invalid option
            echo "Error: invalid option: -$OPTARG" >&2
            exit;;
   esac
done

if [[ $skipNPMInstall == false ]]; then
    if [[ -z $image ]]; then
        echo "Error: you must specify an image with -i."
        exit 1
    fi
    if [[ -z $profile ]]; then
        echo "Error: you must specify a profile with -p."
        exit 1
    fi
fi
if [[ $captureMode != 'none' && $captureMode != 'cpu' && $captureMode != 'memory' && $captureMode != 'trace' ]]; then
    echo "Error: you must specify a valid capture mode with -c."
    exit 1
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
skip install/restart: $skipNPMInstall
image: $image
profile: $profilePath
capture mode: $captureMode
capture area: $captureArea
experiment name: $experimentName
delete action: $deleteAction
save log: $shouldSaveLog
sleep: $shouldSleep

Using the following constants:
namespaces: $numOfNs
create pods and labels: $createDeployments
labels: $numofLabels
label loops: $numofLoopForLabels
delete loops: $numDeleteLoops
cleanup before starting: $cleanupBeforeStarting
run CPU capture in background: $runCPUCaptureInBackground
run trace capture in background: $runTraceCaptureInBackground
trace seconds: $traceSeconds

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
# set -x
if [[ "$deleteAction" = "netpols-and-exit" ]]; then
    deleteAllNetpols
    exit 0
fi

if [[ "$deleteAction" = "ns-and-exit" ]]; then
    cleanUpAllResources
    exit 0
fi

if [[ $cleanupBeforeStarting == "true" ]]; then
    cleanUpAllResources
fi

## deploy NPM (fail if anything goes wrong)
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
    kubectl apply -f $profilePath
    kubectl rollout restart ds azure-npm -n kube-system
    kubectl describe daemonset azure-npm -n kube-system
    set +e
    echo "sleeping to allow NPM pods to come back up after boot up"
    sleep 60
fi

echo "pods to start:"
kubectl get pods -A
echo

echo "netpols to start:"
kubectl get netpol -A
echo

nodeName=`eval kubectl get node | grep -o -m 1 -P 'aks-nodepool\d+-\d+-vmss\d+'`
if [[ -z $nodeName ]]; then
    echo "Could not find a node name"
    exit 1
fi
echo "will obersve node $nodeName"

npmPod=`eval kubectl get pod -A | grep -o -m 1 -P "azure-npm-[0-9a-z]{5}"`
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
    
    echo "waiting for any captures to finish (only necessary if cpu captures are happening in the background)"
    wait
    echo "final capture has finished"
    if [[ $captureMode != "none" ]]; then
        echo "Saving pprof results"
        kubectl cp -n kube-system $npmPod:$podResultsFolderName/ $localResultsFolderName/
    fi
    exit 0
}

execPod () {
    echo "BEGIN COMMAND STDOUT"
    kubectl exec -it $npmPod -n kube-system -- bash -c "$1"
    echo "END COMMAND STDOUT"
}

capture () {
    # first arg is the name for the pprof file
    wait # for other captures to finish

    if [[ $captureArea != "all" && $captureArea != $1 ]]; then
        echo "skipping $1 capture"
        return
    else
        echo "capturing $1"
    fi

    podFileName="$podResultsFolderName/$1"
    if [[ $captureMode == "cpu" ]]; then
        echo "CURRENT POD CPU: $1"
        kubectl top -n kube-system pod $npmPod
        echo "CURRENT NODE CPU: $1"
        kubectl top node $nodeName
        # collect prometheus metrics
        execPod "curl localhost:10091/node-metrics -o $podFileName-node-metrics.out"
        
        echo "getting pprof for cpu: $1"
        commandString="curl localhost:10091/debug/pprof/profile -o $podFileName.out"
        if [[ $runCPUCaptureInBackground == "false" ]]; then
            execPod "$commandString"
        else
            # we want to record while NPM calculations are happening
            # the & makes the command run in the background
            execPod "$commandString" &
        fi
    fi

    if [[ $captureMode == "memory" ]]; then
        # collect initial prometheus metrics
        execPod "curl localhost:10091/node-metrics -o $podFileName-node-metrics-0-seconds.out"

        # capture every 30 seconds until 90 seconds have passed (unless 'don't sleep' option is included, in which case we'll just run once)
        times=1
        if [[ $shouldSleep == "true" ]]; then
            times=4
        fi
        for i in $( seq 1 $times); do
            seconds=$(( 30 * ($i-1) ))
            echo "CURRENT POD MEMORY: $1 - #$seconds seconds later"
            kubectl top -n kube-system pod $npmPod
            echo "CURRENT NODE MEMORY: $1 - #$seconds seconds later"
            kubectl top node $nodeName
            echo "getting pprof for heap: $1 - #$seconds seconds later"
            execPod "curl localhost:10091/debug/pprof/heap -o $podFileName-$seconds-seconds.out"
            if [[ $i != $times ]]; then
                sleep 30
            fi
        done
        if [[ $shouldSleep == "true" ]]; then
            # collect prometheus metrics after 90 seconds
            execPod "curl localhost:10091/node-metrics -o $podFileName-node-metrics-$seconds-seconds.out"
        fi
    fi

    if [[ $captureMode == "trace" ]]; then
        echo "getting pprof for trace: $1"
        if [[ $runTraceCaptureInBackground == "false" ]]; then
            execPod "$commandString"
        else
            wait # for any previous capture to finish (only would happen if the number of namesaces etc. is low)
            # pprof profile looks at CPU usage over 30 seconds, so we want to record while NPM calculations are happening
            # the & makes the command run in the background
            execPod "$commandString" &
        fi
        execPod "curl localhost:10091/debug/pprof/trace?seconds=$traceSeconds -o $podFileName.out" &
    fi
}

if [[ $captureMode != "none" ]]; then
    echo "setting up npm pod environement for capturing"
    execPod "rm -rf $podResultsFolderName && mkdir -p $podResultsFolderName && apt update && apt-get install curl --yes"
fi

if [[ $captureMode != "memory" ]]; then
    capture "dormant"
fi

capture "initial"

echo "Generating $numOfNs namespaces"
generateNs
echo "Done Generating NS"
echo ${namespaces[@]}

if [[ $createDeployments == "true" ]]; then
    kubectl create ns test1replace
    #delete old pod deployments
    rm podDeployments/deployment*.yml
    for i in ${namespaces[@]}; do
        kubectl create ns $i
        sed "s/test1replace/$i/g" podDeployments/nginx_deployment.yaml > podDeployments/deployment-$i.yml
    done
    capture "after-creating-namespaces"

    # Apply all pod deployments
    kubectl apply -f podDeployments/
    capture "after-creating-deployments"

    #Now apply labels to the deployment
    for ns in ${namespaces[@]}; do
        echo "Applying Labels to $ns"
        for (( i=$start; i<=$numofLoopForLabels; i++ ))
        do
            labelAllPodsInNs $ns
        done
    done
    capture "after-labeling-deployments"
fi

for ns in ${namespaces[@]}; do
    kubectl apply -n $ns -f networkPolicies/ 
done
capture "after-creating-netpols"

case $deleteAction in 
    labels-randomly)
        if [[ $createDeployments == "true" ]]; then
            echo "Deleting Random Labels"
            for i in $(seq 1 $numDeleteLoops);do
                echo "Starting delete loop #$i"
                for ns in ${namespaces[@]}; do
                    # TODO actually delete the labels
                    #Re-add labels to new pods
                    labelAllPodsInNs $ns
                    conditionalSleep 2
                done
                if [[ $i != $numDeleteLoops ]]; then
                    conditionalSleep 5
                fi
            done
            capture "after-deleting-labels"
        else
            echo "can't delete pods, didn't create deployments based on config"
        fi
        ;;
    netpols-randomly)
        echo "Deleting Random Policies"
        for i in $(seq 1 $numDeleteLoops);do
            echo "Starting delete loop #$i"
            for ns in ${namespaces[@]}; do
                echo "Deleting random policies in namespace $ns"
                deleteRandomPoliciesNs $ns
                conditionalSleep 3
            done
            if [[ $i != $numDeleteLoops ]]; then
                conditionalSleep 5
            fi
        done
        capture "after-deleting-netpols"
        ;;
    pods-randomly)
        if [[ $createDeployments == "true" ]]; then
            echo "Deleting Random Pods"
            for i in $(seq 1 $numDeleteLoops);do
                echo "Starting delete loop #$i"
                for ns in ${namespaces[@]}; do
                    echo "Deleting random pods in namespace $ns"
                    deleteRandomPodsNs $ns
                    conditionalSleep 2
                done
                if [[ $i != $numDeleteLoops ]]; then
                    conditionalSleep 5
                fi
            done
            capture "after-deleting-pods"
        else
            echo "can't delete pods, didn't create deployments based on config"
        fi
        ;;
    all-after)
        cleanUpAllResources
        capture "after-deleting-all-resources"
        ;;
esac

saveArtifactsAndExit
