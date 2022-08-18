# USE -d to skip running and get num ACLs, pods, IPSets, members
# added ACLs: 2*policies
# added IPSets: 4 + 2*uni*shared + 2*shared
#   [ns-chaos-jr,nsmeta:chaos-jr,hash:xxxx,app:busybox + labels]
# added members: 3 + (5+2*uni+2*shared)*pods
#   [all-ns,nsmeta,nsmeta:chaos-jr + 2*uni*pods + 2*shared*pods + (app,app:busybox,hash,hash:xxxx,ns-chaos-jr) * pods]
numDeployments=2
numReplicas=2
numUniqueLabelsPerPod=2 # must be >= 1
numSharedLabelsPerPod=2 # must be >= 1
numPolicies=2

## SETUP
if [[ $1 == "-d" ]]; then
    DEBUG=true
    echo DEBUGGING
    originalACLs=13
    originalIPSets=47
    originalMembers=96
elif [[ $1 == "-f" ]]; then
    echo only looking at FINAL stuff
    npmPod=`kubectl get pod -n kube-system | grep Running | grep -oP "azure-npm-[a-z0-9]+" -m 1`
    if [[ -z $npmPod ]]; then
        echo "No Linux NPM pod running. Exiting."
        exit 1
    fi
    finalACLs=`kubectl exec -it -n kube-system $npmPod -- curl localhost:10091/cluster-metrics | grep -P "npm_num_iptables_rules \\d+" | grep -oP "\\d+"`
    finalIPSets=`kubectl exec -it -n kube-system $npmPod -- curl localhost:10091/cluster-metrics | grep -P "npm_num_ipsets \\d+" | grep -oP "\\d+"`
    finalMembers=`kubectl exec -it -n kube-system $npmPod -- curl localhost:10091/cluster-metrics | grep -P "npm_num_ipset_entries \\d+" | grep -oP "\\d+"`

    echo final ACLs: $finalACLs
    echo final IPSets: $finalIPSets
    echo final Members: $finalMembers
    exit 0
else
    # linux npm pod
    set -x
    npmPod=`kubectl get pod -n kube-system | grep Running | grep -oP "azure-npm-[a-z0-9]+" -m 1`
    if [[ -z $npmPod ]]; then
        echo "No Linux NPM pod running. Exiting."
        exit 1
    fi

    # windows npm pod
    winNpmPod=`kubectl get pod -n kube-system | grep Running | grep -oP "azure-npm-win-[a-z0-9]+" -m 1`
    if [[ -z $winNpmPod ]]; then
        echo "No Windows NPM pod running. Exiting."
        exit 1
    fi

    kubectl delete ns chaos-jr && echo "sleeping 5 minutes to let NPM ipset count reset" && sleep 5m

    # kubectl exec -it -n kube-system $npmPod -- apt-get install curl -y

    set -e
    echo "fail if curl is uninstalled"
    originalACLs=`kubectl exec -it -n kube-system $npmPod -- curl localhost:10091/cluster-metrics | grep -P "npm_num_iptables_rules \\d+" | grep -oP "\\d+"`
    originalIPSets=`kubectl exec -it -n kube-system $npmPod -- curl localhost:10091/cluster-metrics | grep -P "npm_num_ipsets \\d+" | grep -oP "\\d+"`
    originalMembers=`kubectl exec -it -n kube-system $npmPod -- curl localhost:10091/cluster-metrics | grep -P "npm_num_ipset_entries \\d+" | grep -oP "\\d+"`
    set +e
fi

set +x
numPods=$(( $numDeployments * $numReplicas ))
toAddACLs=$(( 2 * $numPolicies ))
toAddIPSets=$(( 4 + 2 * $numPods * $numUniqueLabelsPerPod + 2 * $numSharedLabelsPerPod))
toAddMembers=$(( 3 + (5 + 2*$numUniqueLabelsPerPod + 2*$numSharedLabelsPerPod) * $numPods ))

totalACLs=$(( $originalACLs + $toAddACLs ))
totalIPSets=$(( $originalIPSets + $toAddIPSets ))
totalMembers=$(( $originalMembers + $toAddMembers ))

currDate=`date`
echo Runing chaos-jr with these constants at $currDate:
echo constants...
echo numDeployments=$numDeployments
echo numReplicas=$numReplicas
echo numUniqueLabelsPerPod=$numUniqueLabelsPerPod
echo numSharedLabelsPerPod=$numSharedLabelsPerPod
echo
echo original ACLs: $originalACLs
echo original IPSets: $originalIPSets
echo original Members: $originalMembers
echo 
echo toAdd ACLs: $toAddACLs
echo toAdd IPSets: $toAddIPSets
echo toAdd Members: $toAddMembers
echo
echo total ACLs: $totalACLs
echo total IPSets: $totalIPSets
echo total Members: $totalMembers
echo
echo numPolicies: $numPolicies
echo numPods: $numPods
echo

if [[ $DEBUG == true ]]; then
    exit 0
fi

sleep 5s

## FILE SETUP
rm pods/*
mkdir -p pods/
rm policies/*
mkdir -p policies/

for i in $(seq 1 $numDeployments); do
    sed "s/TEMP_NAME/dep-$i/g" dep-template.yaml > pods/dep-$i.yaml
    sed -i "s/TEMP_REPLICAS/$numReplicas/g" pods/dep-$i.yaml
done

for i in $(seq 1 $numPolicies); do
    sed "s/TEMP_NAME/policy-$i/g" policy-template.yaml > policies/policy-$i.yaml
    valNum=$i
    if [[ $i -ge $numSharedLabelsPerPod ]]; then
        valNum=$(( $numSharedLabelsPerPod - 1 ))
    fi
    sed -i "s/TEMP_LABEL_NAME/lab-$valNum/g" policies/policy-$i.yaml
    sed -i "s/TEMP_LABEL_VAL/val-$valNum/g" policies/policy-$i.yaml
done

## RUN
echo "STARTING RUN"
echo
set -x
kubectl delete ns chaos-jr --ignore-not-found
kubectl create ns chaos-jr

kubectl apply -f pods/

set +x
sharedLabels="lab-1=val-1"
for i in $(seq 2 $numSharedLabelsPerPod); do
    sharedLabels="$sharedLabels lab-$i=val-$i"
done
set -x
kubectl label pods -n chaos-jr --all $sharedLabels

set +x
count=1
for pod in $(kubectl get pods -n chaos-jr -o jsonpath='{.items[*].metadata.name}'); do
    uniqueLabels=uni-lab-$count=uni-val-$count
    count=$(( $count + 1 ))
    for i in $(seq 2 $numUniqueLabelsPerPod); do
        uniqueLabels="$uniqueLabels uni-lab-$count=uni-val-$count"
        count=$(( $count + 1 ))
    done
    set -x
    kubectl label pods -n chaos-jr $pod $uniqueLabels
    set +x
done

set -x
kubectl apply -f policies/
set +x

## FINAL CHECK
echo
echo FINISHED
echo
echo verify final numbers
set -x
sleep 10s
finalACLs=`kubectl exec -it -n kube-system $npmPod -- curl localhost:10091/cluster-metrics | grep -P "npm_num_iptables_rules \\d+" | grep -oP "\\d+"`
finalIPSets=`kubectl exec -it -n kube-system $npmPod -- curl localhost:10091/cluster-metrics | grep -P "npm_num_ipsets \\d+" | grep -oP "\\d+"`
finalMembers=`kubectl exec -it -n kube-system $npmPod -- curl localhost:10091/cluster-metrics | grep -P "npm_num_ipset_entries \\d+" | grep -oP "\\d+"`
set +x

echo final ACLs: $finalACLs. estimated $totalACLs
echo final IPSets: $finalIPSets. estimated $totalIPSets
echo final Members: $finalMembers. estimated $totalMembers
echo "to get up-to-date results later, run this script with the -f flag"

## OLD CODE
# resultsFile=$1
# if [[ -z $resultsFile ]]; then
#     echo "No results file specified"
#     exit 1
# fi
# test -f $resultsFile && echo "Results file $resultsFile already exists. Exiting." && exit 1
