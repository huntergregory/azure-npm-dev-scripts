#!/bin/bash
## PARAMETERS
if [[ $# != 4 ]]; then
	echo "need 4 args"
fi
containerName=$1
localConfigFile=$2
scriptToRun=$3 # needs to be in this dir

## CONSTANTS
dockerImage=k8s-and-go
dockerKubeFolder=/root/.kube
dockerBaseFolder=/azure-npm-dev-scripts
dockerScriptFolder=$dockerBaseFolder/azure-npm-dev-scripts/run-docker
resultsFolder=../../run-docker-output

outputFile=$resultsFolder/$containerName

## BEGIN SCRIPT
set -x
# build the image
docker images | grep $dockerImage || exit_code=$?
if [[ $exit_code -ne 0 ]]; then
    echo "Build the image since it does not exist."
    docker build -t $dockerImage -f ../k8s-and-go.Dockerfile .
fi

## create and setup a container with the kube config
docker ps | grep ${containerName} || exit_code=$?
if [[ $exit_code -eq 0 ]]; then
	echo "docker container $containerName already exists."
	exit 1
fi
# fail the script if any setup for the docker environment fails
set -e
mkdir -p $resultsFolder
test -f $outputFile || exit_code=$?
if [[ $exit_code -eq 0 ]]; then
	echo "output file $outputFile already exists"
	exit 1
fi
test -f $localConfigFile
test -f $scriptToRun
docker run -it -d --name $containerName $dockerImage
docker exec $containerName mkdir -p $dockerBaseFolder
# copy the repo over to the container
docker cp ../ $containerName:$dockerBaseFolder/
docker exec $containerName mkdir -p $dockerKubeFolder
docker cp $localConfigFile $containerName:$dockerKubeFolder/config

## run the experiment
set +e
docker exec -it $containerName bash -c "cd $dockerScriptFolder && chmod +x $scriptToRun && ./$scriptToRun" > $outputFile
echo "Finished running experiment."

