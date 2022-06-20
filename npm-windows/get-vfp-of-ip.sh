ip=$1
nodepoolName=akswin22
npmName=azure-npm # azure-npm-win
anyIP=false
if [[ $ip == "" ]]; then
    echo "Specify an ip, or 'ANY' + a node name"
    exit 1
elif [[ $ip == "ANY" ]]; then
    echo "going to use any IP"
    anyIP=true
    node=$2
    if [[ $node == "" ]]; then
        echo "Specify a node if using 'ANY' ip"
        exit 1
    fi
fi

if [[ $anyIP == true ]]; then
    # this will be a space/line-separated list of IPs
    ip=`kubectl get pod -A -owide | grep $node | grep -oP "\d+\\.\d+\\.\d+\\.\d+"`
    if [[ $ip == "" ]]; then
        echo "Could not find any pod IP on the node $node"
        exit 1
    fi
    echo "will use one of these IPs $ip"
else
    node=`kubectl get pod -A -owide | grep $ip | grep -oP "${nodepoolName}\d+"`
    if [[ $? != 0 ]]; then
        echo "Couldn't find IP"
        exit 1
    fi
    echo "$ip is on node $node"
fi

npmPod=`kubectl get pod -n kube-system -owide | grep $npmName | grep $node`
if [[ $? != 0 ]]; then
    echo "Couldn't find $npmName pod"
    exit 1
fi
npmPod=`echo $npmPod |  awk '{print $1}'`
echo "$npmPod is on the same node"

endpointRegex="[a-zA-Z0-9\\-]+"
# search for each space/line-separated item
for x in $ip; do
    echo "seeing if $x is referenced in NPM logs"
    endpointID=`kubectl logs -n kube-system $npmPod | grep "updating endpoint cache" | grep $x | grep -oP "id:$endpointRegex" | grep -oP "$endpointRegex" | grep -v id | tail -n 1`
    if [[ $endpointID != "" ]]; then
        echo "Endpoint ID for $x is $endpointID"
        break
    fi
done
if [[ $endpointID == "" ]]; then
    echo "Couldn't find any endpointID. Restart NPM to get fresh logs"
    exit 1
fi

port=`kubectl exec -it -n kube-system $npmPod -- powershell.exe vfpctrl /list-vmswitch-port | grep -i $endpointID -B 1 | grep "Port name" | grep -oP ": $endpointRegex" | grep -oP "$endpointRegex"`
if [[ $? != 0 ]]; then
    echo "Couldn't find port"
    exit 1
fi
echo "port: $port"

fileSuffix=IP_${ip}_EP_${endpointID}_port_${port}.txt
# Think this file is a binary file, not a text file. It prints out weird.
# TODO Ideally would be text file...
kubectl exec -it -n kube-system $npmPod -- powershell.exe vfpctrl /port $port /list-tag > vfp-tags-$fileSuffix
kubectl exec -it -n kube-system $npmPod -- powershell.exe vfpctrl /port $port /layer ACL_ENDPOINT_LAYER /list-rule | grep azure-acl -B 1 -A 10 > acls-$fileSuffix

echo
echo "results written to vfp-tags-$fileSuffix and acls-$fileSuffix"
