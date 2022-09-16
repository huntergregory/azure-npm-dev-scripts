# fail if any command fails
set -e

## Configuration
myLocation="eastus2euap" # Depends on you
myResourceGroup="TODO" # # Depends on you
myAKSCluster=$myResourceGroup # Depends on you
myWindowsUserName="azureuser" # Recommend azureuser
myWindowsPassword="TODO" # Complex enough
myK8sVersion="1.23.8" # AKS supports WS2022 when k8s version >= 1.23
myWindowsNodePool="win22" # Length <= 6
myLinuxNodePool="linux1"

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

# default VM SKU: Standard_DS2_v2 (~8 GB)
az aks create \
    --resource-group $myResourceGroup \
    --name $myAKSCluster \
    --generate-ssh-keys \
    --windows-admin-username $myWindowsUserName \
    --windows-admin-password $myWindowsPassword \
    --kubernetes-version $myK8sVersion \
    --network-plugin azure \
    --vm-set-type VirtualMachineScaleSets \
    --node-count 1 \
    --max-pods 200 \
    --network-policy azure \
    --uptime-sla

# default VM SKU: Standard_D2s_v3 (~8 GB)
# for ~16 GB memory, use --node-vm-size=Standard_D4s_v3
az aks nodepool add \
    --resource-group $myResourceGroup \
    --cluster-name $myAKSCluster \
    --name $myWindowsNodePool \
    --os-type Windows \
    --os-sku Windows2022 \
    --max-pods 200 \
    --node-count 1

az aks nodepool add \
    --resource-group $myResourceGroup \
    --cluster-name $myAKSCluster \
    --name $myLinuxNodePool \
    --os-type Linux \
    --os-sku Ubuntu \
    --max-pods 200 \
    --node-vm-size=Standard_D2s_v3 \
    --node-count 1

az aks get-credentials -g $myResourceGroup -n $myAKSCluster --overwrite-existing
