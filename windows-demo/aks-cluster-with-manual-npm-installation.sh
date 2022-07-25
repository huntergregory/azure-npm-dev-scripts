set -e

myLocation="eastus2euap" # Depends on you
myResourceGroup="TODO" # Depends on you
myAKSCluster=$myResourceGroup # Depends on you
myWindowsUserName="azureuser" # Recommend azureuser
myWindowsPassword="TODO" # Complex enough
myK8sVersion="1.23" # AKS supports WS2022 when k8s version >= 1.23
myWindowsNodePool="win22" # Length <= 6

# Update aks-preview to the latest version
az extension add --name aks-preview
az extension update --name aks-preview

# Enable Microsoft.ContainerService/AKSWindows2022Preview
az feature register --namespace Microsoft.ContainerService --name AKSWindows2022Preview
# for public preview, will be able to register for Windows Network Policies
# az feature register --namespace Microsoft.ContainerService --name WindowsNetworkPolicyPreview
az provider register -n Microsoft.ContainerService

az group create --name $myResourceGroup --location $myLocation

# for public preview and general availability, won't need to apply the yamls below and can just add the following to the create command: --network-policy azure
az aks create \
    --resource-group $myResourceGroup \
    --name $myAKSCluster \
    --generate-ssh-keys \
    --windows-admin-username $myWindowsUserName \
    --windows-admin-password $myWindowsPassword \
    --kubernetes-version $myK8sVersion \
    --network-plugin azure \
    --vm-set-type VirtualMachineScaleSets
    --node-count 1

az aks nodepool add \
    --resource-group $myResourceGroup \
    --cluster-name $myAKSCluster \
    --name $myWindowsNodePool \
    --os-type Windows \
    --os-sku Windows2022 \
    --node-count 1

# uncomment below line to force pods to be scheduled on windows nodes
# az aks nodepool update --node-taints CriticalAddonsOnly=true:NoSchedule -n nodepool1 -g $myResourceGroup --cluster-name $myAKSCluster

# will set current kubectl context
az aks get-credentials -g $myResourceGroup -n $myAKSCluster --overwrite-existing

# NPM on Linux
kubectl apply -f https://raw.githubusercontent.com/Azure/azure-container-networking/master/npm/azure-npm.yaml
# NPM on Windows
kubectl apply -f https://raw.githubusercontent.com/Azure/azure-container-networking/master/npm/examples/windows/azure-npm.yaml
