numPods=`kubectl get pod -A | grep npm | wc -l`
numRunningPods=`kubectl get pod -A | grep npm | grep Running | wc -l`
if [[ $numPods == 0 ]]; then
    echo "No pods found"
    exit 1
elif [[ $numRunningPods != $numPods ]]; then
    echo "Not all pods are running"
    exit 1
fi
npmPods=`kubectl get pod -A | grep -o -P "azure-npm-[0-9a-z]{5}"`
for pod in $npmPods; do
    echo "Resetting kernel for $pod"
    
    kubectl exec -it $pod -n kube-system -- bash -c "iptables -w 30 -D FORWARD -j AZURE-NPM -m conntrack --ctstate NEW"
    kubectl exec -it $pod -n kube-system -- bash -c "iptables -vnL | grep 'Chain AZURE-NPM' | awk '{print \$2}' | xargs -n 1 iptables -w 30 -F"
    kubectl exec -it $pod -n kube-system -- bash -c "iptables -vnL | grep 'Chain AZURE-NPM' | awk '{print \$2}' | xargs -n 1 iptables -w 30 -X"
    numChains=`kubectl exec -it $pod -n kube-system -- bash -c "iptables -vnL | grep 'Chain AZURE-NPM'" | wc -l`
    echo "num npm chains left: $numChains"
    if [[ $numChains != 0 ]]; then
        echo "Failed to delete all chains"
        exit 1
    fi

    kubectl exec -it $pod -n kube-system -- bash -c "ipset -L --name | grep azure-npm- | awk '{print \"-F \"\$1}' | ipset restore"
    kubectl exec -it $pod -n kube-system -- bash -c "ipset -L --name | grep azure-npm- | awk '{print \"-X \"\$1}' | ipset restore"
    numIPSets=`kubectl exec -it $pod -n kube-system -- bash -c "ipset -L --name | grep azure-npm-" | wc -l`
    echo "num npm ipsets left: $numIPSets"
    if [[ $numIPSets != 0 ]];
    then
        echo "Error: ipsets not deleted"
        exit 1
    fi
done

# 750 running pods, 55 ns, 1351 netpols
