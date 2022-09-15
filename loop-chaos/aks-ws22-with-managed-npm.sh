set -e

myLocation="centraluseuap" # Depends on you
myResourceGroup="TODO" # # Depends on you
myAKSCluster=$myResourceGroup # Depends on you
myWindowsUserName="azureuser" # Recommend azureuser
myWindowsPassword="TODO" # Complex enough
myK8sVersion="1.23.8" # AKS supports WS2022 when k8s version >= 1.23
myWindowsNodePool="win22" # Length <= 6

## Update aks-preview to the latest version
az extension add --name aks-preview
az extension update --name aks-preview

## Enable Microsoft.ContainerService/AKSWindows2022Preview
az feature register --namespace Microsoft.ContainerService --name AKSWindows2022Preview
az feature register --namespace Microsoft.ContainerService --name WindowsNetworkPolicyPreview 
az provider register -n Microsoft.ContainerService

## Create the resource group and cluster
echo "creating cluster $myAKSCluster at $(date) in region $myLocation and RG $myResourceGroup"
az group create --name $myResourceGroup --location $myLocation

az aks create \
    --resource-group $myResourceGroup \
    --name $myAKSCluster \
    --generate-ssh-keys \
    --windows-admin-username $myWindowsUserName \
    --windows-admin-password $myWindowsPassword \
    --kubernetes-version $myK8sVersion \
    --network-plugin azure \
    --node-vm-size "Standard_DS2_v2" \
    --node-count 1 \
    --network-policy azure \
    --uptime-sla
# NOTE: use uptime sla to prevent/limit issues with API Server uptime

# more likely to see memory issues with Standard_DS2_v2 (~8 GB)
# for our tests, we use Standard_D4s_v3 (~15 GB) to avoid memory issues
az aks nodepool add \
    --resource-group $myResourceGroup \
    --cluster-name $myAKSCluster \
    --name $myWindowsNodePool \
    --os-type Windows \
    --os-sku Windows2022 \
    --node-count 1 \
    --node-vm-size Standard_DS2_v2 \
    --max-pods 150

## UNCOMMENT to prevent customer pods from being scheduled on Linux nodes
# az aks nodepool update --node-taints CriticalAddonsOnly=true:NoSchedule -n nodepool1 -g $myResourceGroup --cluster-name $myAKSCluster

## get kubeconfig
az aks get-credentials -g $myResourceGroup -n $myAKSCluster --overwrite-existing
