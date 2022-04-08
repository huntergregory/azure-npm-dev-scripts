#!/bin/bash
## CONSTANTS
start=1
numOfNs=600 # 15 replicas per namespace
numofLabels=50
numofLoopForLabels=1
numDeleteLoops=2

cleanupBeforeStarting=false
podFileName=pods_in_ns.txt
policyFileName=netpols_in_ns.txt
logFileName=npm.log
# background=true doesn't work currently since there's a background process for capturing logs
runCPUCaptureInBackground=false
runTraceCaptureInBackground=false
traceSeconds=30

## arrays
namespaces=()
labelsArray=(chaos=true)

## PARAMETERS
help () {
    echo "This script creates resources and can capture performance metrics e.g. exec times, cpu, memory, and tracing."
    echo "The script can create namespaces, deployments, and network policies, and label the deployments."
    echo "It can be as chaotic as you want based on global constants in the script."
    echo
    echo "Usage:"
    echo "./npm-chaos.sh {-s}|{-i <npm-image> -p <npm-profile-name>} [-n <experiment-name] [-d <delete-action>] [-c <capture-mode>] [-t <minutes-for-memory-capture>] [-a <capture-area>] [-r <what-to-create>] [-l] [-x]"
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
    echo "-c <capture-mode"
    echo "    Capture pprof for the specified mode. Can be 'cpu', 'memory', or 'trace'."
    echo "-t <minutes-for-memory-capture>"
    echo "    Capture memory for the specified number of minutes. Default is 1. Ignored if -c is not 'memory' or if -x is used"
    echo "-a <capture-area>"
    echo "    Default is 'all'. Can be set to 'initial', 'after-creating-netpols', etc. to only perform one capture (specifically, the line of code: 'capture \"<capture-area>\"')."
    echo "-r <what-to-create>"
    echo "    Options are 'all', 'netpols', 'pods', or 'none'. Default is 'all'."
    echo "-l"
    echo "    Save the NPM log after finishing."
    echo "-x"
    echo "    Don't sleep."
    echo "-h"
    echo "    Print this help message."
}

if [[ "$#" == 0 ]]; then
    help
    exit 1
fi

memCaptureTimes=1
createDeployments=true
createNetPols=true
skipNPMInstall=false
experimentName="experiment"
captureMode="no-capture"
shouldSaveLog=false
shouldSleep=true
deleteAction="all-after"
captureArea="all"
while getopts ":i:p:n:d:c:t:a:r:slxh" option; do
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
        t)
            memCaptureTimes=$OPTARG;;
        a)
            captureArea=$OPTARG;;
        n)
            experimentName=$OPTARG;;
        x)
            shouldSleep=false;;
        r)
            whatToCreate=$OPTARG
            if [[ $whatToCreate == 'netpols' ]]; then
                echo "ONLY CREATING NETPOLS"
                createNetPols=true
                createDeployments=false
            elif [[ $whatToCreate == 'pods' ]]; then
                echo "ONLY CREATING PODS"
                createDeployments=true
                createNetPols=false
            elif [[ $whatToCreate == 'none' ]]; then
                echo "NOT CREATING ANYTHING"
                createDeployments=false
                createNetPols=false
            else
                echo "CREATING ALL"
                createDeployments=true
                createNetPols=true
            fi
            ;;
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
if [[ $captureMode != 'no-capture' && $captureMode != 'cpu' && $captureMode != 'memory' && $captureMode != 'trace' ]]; then
    echo "Error: you must specify a valid capture mode with -c."
    exit 1
fi
profilePath="npm-profiles-with-pprof/$profile.yaml"
if [[ $skipNPMInstall == false ]]; then
    test -f $profilePath
    if [[ $? != 0 ]]; then
        echo "Error: profile $profilePath does not exist."
        exit 1
    fi
fi

podResultsFolderName="/npm-chaos-results/$experimentName/$captureMode"
localResultsFolderName="../npm-chaos-results/$experimentName/$captureMode"
test -d $localResultsFolderName && echo "Error: $localResultsFolderName already exists." && exit 1

## when using docker exec ... npm-chaos.sh, the execution will start at the root folder (/), so we need to move into the repo
echo "Original working directory:"
pwd
echo "Attempting to cd into azure-npm-dev-scripts/   (this will create an error message if already in that folder)"
cd azure-npm-dev-scripts/
echo "Working directory after cd:"
pwd

## display and write config to file
set -ex
mkdir -p $localResultsFolderName
set +ex
cat > $localResultsFolderName/chaos-parameters.txt << EOF
Running NPM Chaos with the following config:
skip install/restart: $skipNPMInstall
image: $image
profile: $profilePath
capture mode: $captureMode
minutes to capture memory for: $memCaptureTimes
capture area: $captureArea
experiment name: $experimentName
create pods and labels: $createDeployments
create netpols: $createNetPols
delete action: $deleteAction
save log: $shouldSaveLog
sleep: $shouldSleep

Using the following constants:
namespaces: $numOfNs
x 27 policies: $((numOfNs * 27))
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
        namespace="web-$sufix-$i"
        namespaces=("${namespaces[@]}" $namespace)
    done
    if [[ $createNetPols == true || $createDeployments == true ]]; then
        echo "Creating $numOfNs namespaces"
        for i in ${namespaces[@]}; do
            kubectl create ns $i
        done
        echo "Done creating NS"
        echo ${namespaces[@]}
    fi
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
    kubectl get pods -n $1 | grep -v "NAME" | awk '{print $1}' > $podFileName

    #get 10 random pods and delete them
    podname=$(shuf -n 10 $podFileName | xargs)
    kubectl delete pod -n $1 $podname
}

deleteRandomPoliciesNs () {    
    echo "Deleting random Network Policies in namespace $1"
    #list all pods in the namespace into a file
    kubectl get netpol -n $1 | grep -v "NAME" | awk '{print $1}' > $policyFileName

    #get 10 random netpols and delete them
    polname=$(shuf -n 10 $policyFileName | xargs)
    kubectl delete netpol -n $1 $polname
}

deleteAllNetpols () {
    for ns in ${namespaces[@]}; do
        kubectl get netpol -n $ns | grep -v "NAME" | awk '{print $1}' > $policyFileName

        polname=$(cat $policyFileName | xargs)
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

generateNs

if [[ "$deleteAction" = "ns-and-exit" ]]; then
    cleanUpAllResources
    exit 0
fi

if [[ $cleanupBeforeStarting == "true" && ($createDeployments == true || $createNetPols == true) ]]; then
    cleanUpAllResources
fi

## deploy NPM (fail if anything goes wrong)
if [[ $skipNPMInstall == true ]]; then
    echo "Skipping NPM installation/restart"
else
    echo "Deploying NPM"
    set -ex
    echo "(re)deploying NPM with profile $profile and image $image"
    kubectl apply -f https://raw.githubusercontent.com/Azure/azure-container-networking/master/npm/azure-npm.yaml
    # swap azure-npm image with desired one
    kubectl set image daemonset/azure-npm -n kube-system azure-npm=$image
    # swap NPM profile with desired one
    kubectl apply -f $profilePath
    kubectl rollout restart ds azure-npm -n kube-system
    set +ex
    echo "sleeping to allow NPM pods to come back up after boot up"
    sleep 180
    kubectl describe daemonset azure-npm -n kube-system
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
    if [[ $skipNPMInstall == false || $shouldSaveLog == true ]]; then
        echo "Could not find NPM pod"
        exit 1
    fi
fi
echo "will observe NPM pod: $npmPod"
# print out image version
kubectl get pod -n kube-system $npmPod -o yaml | grep image: -m 1

if [[ $shouldSaveLog == "true" ]]; then
    logFilePath="$localResultsFolderName/$logFileName"
    echo "Saving npm logs to $logFilePath in a background process"
    kubectl logs -n kube-system $npmPod -f > $logFilePath &
fi

saveArtifactsAndExit () {
    if [[ $captureMode == "cpu" ]]; then
        echo "waiting for any captures to finish (only necessary if cpu captures are happening in the background)"
        sleep 70 # capture takes 60 seconds
        echo "final capture has finished"
    fi
    if [[ $captureMode != "no-capture" ]]; then
        echo "Saving pprof results"
        kubectl cp -n kube-system $npmPod:$podResultsFolderName/ $localResultsFolderName/
    fi
    # kill the background processes (the logs) that have this process' pid (i.e. $$) as a parent
    pkill -P $$
    exit 0
}

execPod () {
    echo "BEGIN COMMAND STDOUT"
    kubectl exec -it $npmPod -n kube-system -- bash -c "$1"
    echo "END COMMAND STDOUT"
}

if [[ $captureMode != "no-capture" ]]; then
    topFile=$localResultsFolderName/kubectl-top-captures.txt
    echo "All Kubectl Top Captures" > $topFile
fi
capture () {
    # first arg is the name for the pprof file
    if [[ $captureMode != "no-capture" ]]; then
        if [[ $captureArea != "all" && $captureArea != $1 ]]; then
            echo "skipping $1 capture" | tee -a $topFile
            return
        else
            echo "capturing $1" | tee -a $topFile
        fi
    fi

    resultsFileName="$podResultsFolderName/$1"
    if [[ $captureMode == "cpu" ]]; then
        echo "CURRENT POD CPU: $1" | tee -a $topFile
        kubectl top -n kube-system pod $npmPod | tee -a $topFile
        echo "CURRENT NODE CPU: $1" | tee -a $topFile
        kubectl top node $nodeName | tee -a $topFile

        # collect prometheus metrics
        echo "NODE METRICS: $1" | tee -a $topFile
        execPod "curl localhost:10091/node-metrics" | tee -a $topFile

        echo "getting pprof for cpu: $1"
        commandString="curl localhost:10091/debug/pprof/profile -o $resultsFileName.out"
        if [[ $runCPUCaptureInBackground == "false" ]]; then
            execPod "$commandString"
        else
            wait # for any previous capture to finish (only would happen if the number of namesaces etc. is low)
            # we want to record while NPM calculations are happening
            # the & makes the command run in the background
            execPod "$commandString" &
        fi
    fi

    if [[ $captureMode == "memory" ]]; then
        # collect initial prometheus metrics
        execPod "curl localhost:10091/node-metrics -o $resultsFileName-node-metrics-0-seconds.out"

        # capture periodically (unless 'don't sleep' option is included, in which case we'll just run once)
        if [[ $shouldSleep != "true" ]]; then
            memCaptureTimes=1
        fi
        for i in $( seq 1 $memCaptureTimes); do
            minutes=$(( $i-1 ))
            echo "CURRENT POD MEMORY: $1 - $minutes minutes later" | tee -a $topFile
            kubectl top -n kube-system pod $npmPod | tee -a $topFile
            echo "CURRENT NODE MEMORY: $1 - $minutes minutes later" | tee -a $topFile
            kubectl top node $nodeName | tee -a $topFile

            echo "getting pprof for heap: $1 - $minutes minutes later"
            execPod "curl localhost:10091/debug/pprof/heap -o $resultsFileName-$minutes-minutes.out"

            echo "NODE METRICS: $1 - $minutes minutes later" | tee -a $topFile
            execPod "curl localhost:10091/node-metrics" | tee -a $topFile

            if [[ $i != $memCaptureTimes ]]; then
                sleep 60
            fi
        done
    fi

    if [[ $captureMode == "trace" ]]; then
        echo "getting pprof for trace: $1"
        commandString="curl localhost:10091/debug/pprof/trace?seconds=$traceSeconds -o $resultsFileName.out"
        # go tool trace -http :8081 trace.out
        if [[ $runTraceCaptureInBackground == "false" ]]; then
            execPod "$commandString"
        else
            wait # for any previous capture to finish (only would happen if the number of namesaces etc. is low)
            # pprof profile looks at CPU usage over 30 seconds, so we want to record while NPM calculations are happening
            # the & makes the command run in the background
            execPod "$commandString" &
        fi
    fi
}

if [[ $captureMode != "no-capture" ]]; then
    echo "setting up npm pod environement for capturing"
    execPod "rm -rf $podResultsFolderName && mkdir -p $podResultsFolderName && apt-get install curl --yes" # apt update && 
fi

if [[ $captureMode != "memory" ]]; then
    capture "dormant"
fi

capture "initial"

if [[ $createDeployments == "true" ]]; then
    echo "creating extra namespace 'test1replace'"
    kubectl create ns test1replace
    #delete old pod deployments
    rm podDeployments/deployment*.yml
    for i in ${namespaces[@]}; do
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

if [[ $createNetPols == "true" ]]; then
    for ns in ${namespaces[@]}; do
        kubectl apply -n $ns -f networkPolicies/ 
    done
    capture "after-creating-netpols"
fi

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
