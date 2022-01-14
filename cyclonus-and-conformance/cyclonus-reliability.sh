#!/usr/bin/env bash
## inspired by cyclonus and conformance tests at https://github.com/Azure/azure-container-networking/
## CONSTANTS
dockerImage=k8s-and-go
dockerBaseFolder=/azure-npm-dev-scripts
dockerCyclonusFile=$dockerBaseFolder/cyclonus-and-conformance/cyclonus.sh

## PARAMETERS
help () {
	echo "This script runs cyclonus in parallel docker containers."
    echo
    echo "Usage:"
    echo "./cylconus-reliability.sh -g <azure-resource-group> -n <experiment-name> -c <count> -i <npm-image> -p <npm-profile-name> [-d]"
	echo "-g"
	echo "    The azure resource group to create clusters in."
    echo "-n <experiment-name>"
    echo "    Specify an experiment name."
    echo "-c <count>"
    echo "    Specify the number of cyclonus tests to run in parallel."
	echo "-d"
	echo "    Delete and create a new container if it already exists."
    echo "-i <npm-image>"
    echo "    The NPM image."
    echo "-p <npm-profile-name>"
    echo "    The name of the NPM profile (without the file path or '.yaml')."
    echo "-h"
    echo "    Print this help message."
}

if [[ "$#" == 0 ]]; then
    help
    exit 1
fi

shouldDeleteExistingContainer=false
while getopts ":g:n:c:i:p:dh" option; do
    case $option in
        g)
            resourceGroup=$OPTARG;;
        n)
            experimentName=$OPTARG;;
        c)
            count=$OPTARG;;
        i)
            image=$OPTARG;;
        p)
            profile=$OPTARG;;
        d)
            shouldDeleteExistingContainer=true;;
        h)
            help
            exit 0;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            exit 1;;
   esac
done

if [[ -z $resourceGroup || -z $experimentName || -z $count || -z $image || -z $profile ]]; then
	echo "missing a required parameter"
	exit 1
fi

## finish setup
# results folder needs to be outside the repo so we don't copy it to the docker container
localResultsFolder=../../npm-cyclonus-reliability-results/$experimentName
dockerResultsFolder=/npm-cyclonus-results
dockerCyclonusResultsFile=$dockerResultsFolder/cyclonus-test.txt
dockerNPMLogsFile=$dockerResultsFolder/npm-logs.txt

## display and write config to file
set -ex
mkdir -p $localResultsFolder
set +ex
cat > $localResultsFolder/parameters.txt << EOF
Running NPM Chaos in a docker container with the following config:
experiment name: $experimentName
experiment count: $count
image: $image
profile: $profile
delete existing container: $shouldDeleteExistingContainer

Using the following constants:
dockerImage: $dockerImage
localResultsFolder: $localResultsFolder
dockerResultsFolder: $dockerResultsFolder

EOF

cat $localResultsFolder/parameters.txt

## BEGIN SCRIPT
## SETUP
set -e # fail the script if any setup fails

docker images | grep $dockerImage || exit_code=$?
if [[ $exit_code -ne 0 ]]; then
    echo "Build the image since it does not exist."
    docker build -t $dockerImage -f k8s-and-go.Dockerfile .
fi

echo "SETTING UP ALL CONTAINERS"
for i in $(seq 1 $count); do
    containerName=$experimentName$i
    echo "Creating container $containerName"
    ## create and setup a container with the kube config
    docker ps | grep ${containerName} || exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        echo "docker container $containerName already exists for this kube config."
        if [[ $shouldDeleteExistingContainer == "true" ]]; then
            echo "deleting the old container and creating a new one."
            docker stop $containerName && docker rm $containerName
        else
            echo "NOT running the experiment. To delete an existing container and create a new one, use -d."
            exit 1
        fi
    fi
    docker run -it -d --name $containerName $dockerImage
    docker exec $containerName mkdir -p $dockerBaseFolder
    # copy the repo over to the container
    docker cp ../. $containerName:$dockerBaseFolder/
    docker exec $containerName chmod +x $dockerCyclonusFile
done

echo "SETTING UP ALL CLUSTERS @ $(date)"
# az group create --name $resourceGroup --location westus2
seq 1 $count | xargs -n 1 -P $count -I {} bash -c "az aks create -g $resourceGroup -n '$experimentName{}' --node-count 3 --network-plugin azure --network-policy azure"

echo "CONFIGURING CONTAINERS WITH THEIR CLUSTERS @ $(date)"
for i in $(seq 1 $count); do
    containerName=$experimentName$i
    clusterName=$resourceGroup--$experimentName$i
    echo "Setting up $containerName for cluster $clusterName."
    dockerKubeFolder=/root/.kube
    docker exec $containerName mkdir -p $dockerKubeFolder
    folder=$localResultsFolder/container$i
    mkdir -p $folder
    kubeConfigFile=$folder/config
    az aks get-credentials -g $resourceGroup -n $containerName -f $kubeConfigFile
    docker cp $kubeConfigFile $containerName:$dockerKubeFolder/config
done
set +e

## EXPERIMENTS
echo "RUNNING ALL CONTAINERS @ $(date)"
seq 1 $count | xargs -n 1 -P $count -I {} bash -c "docker exec '$experimentName{}' $dockerCyclonusFile -i $image -p $profile"

for i in $( seq 1 $count ); do
    containerName=$experimentName$i
    folder=$localResultsFolder/container$i
    echo "Copying results from container $containerName to $folder."
    docker cp $containerName:$dockerCyclonusResultsFile $folder
    docker cp $containerName:$dockerNPMLogsFile $folder
done

az group delete -n $resourceGroup -y
