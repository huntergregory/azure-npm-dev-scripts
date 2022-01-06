#!/bin/bash
## add vm0, vm1, vm2 to three vms
set -x
i=0
nodeName=""
kubectl get node | grep -m 3 -o -P "aks-nodepool\d-\d+-vmss\d+" | while read -r line ; do
	nodeName=$line
	kubectl label node $nodeName vm=$i
	i=$((i+1))
done
