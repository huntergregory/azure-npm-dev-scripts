# This script uses az CLI and kubectl to create AKS cluster 
# with 1 Linux node and 1 Windows Server 2022 nodes
# with Azure NPM installed on both Linux and Windows nodes.

set -e

myLocation="eastus2euap" # Depends on you
myResourceGroup="TODO"
myAKSCluster=$myResourceGroup # Depends on you
myWindowsUserName="azureuser" # Recommend azureuser
myWindowsPassword="TODO" # Complex enough
myWindowsNodePool="win22" # Length <= 6

# Update aks-preview to the latest version
az extension add --name aks-preview
az extension update --name aks-preview

# for public preview, will be able to register for Windows Network Policies
# az feature register --namespace Microsoft.ContainerService --name WindowsNetworkPolicyPreview
# az provider register -n Microsoft.ContainerService

az group create --name $myResourceGroup --location $myLocation

# for public preview and general availability, won't need to apply the yamls below and can just add the following to the create command: --network-policy azure
az aks create \
    --resource-group $myResourceGroup \
    --name $myAKSCluster \
    --generate-ssh-keys \
    --windows-admin-username $myWindowsUserName \
    --windows-admin-password $myWindowsPassword \
    --network-plugin azure \
    --vm-set-type VirtualMachineScaleSets \
    --node-vm-size "Standard_DS2_v2" \
    --node-count 1 \
    --max-pods 80 \
    --uptime-sla

az aks nodepool add \
    --resource-group $myResourceGroup \
    --cluster-name $myAKSCluster \
    --name $myWindowsNodePool \
    --os-type Windows \
    --os-sku Windows2022 \
    --node-vm-size "Standard_D4_v2" \
    --node-count 1 \
    --max-pods 100

    # standard_d4s_v3 exceeds limit in centraluseuap

# uncomment below line to force pods to be scheduled on windows nodes
# az aks nodepool update --node-taints CriticalAddonsOnly=true:NoSchedule -n nodepool1 -g $myResourceGroup --cluster-name $myAKSCluster

# will set current kubectl context
az aks get-credentials -g $myResourceGroup -n $myAKSCluster --overwrite-existing

# NPM on Linux
kubectl apply -f https://raw.githubusercontent.com/Azure/azure-container-networking/master/npm/azure-npm.yaml
kubectl set image ds -n kube-system azure-npm azure-npm=mcr.microsoft.com/containernetworking/azure-npm:v1.4.32
# NPM on Windows
kubectl apply -f https://raw.githubusercontent.com/Azure/azure-container-networking/master/npm/examples/windows/azure-npm.yaml
kubectl set image ds -n kube-system azure-npm-win azure-npm=mcr.microsoft.com/containernetworking/azure-npm:v1.4.34
