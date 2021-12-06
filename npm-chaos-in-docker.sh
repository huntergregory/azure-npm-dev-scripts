#!/bin/bash
## CONSTANTS
dockerImage=k8s-and-go

dockerBaseFolder=/azure-npm-dev-scripts
dockerChaosFile=$dockerBaseFolder/npm-chaos.sh
localKubeConfigFolder=~/.kube

## PARAMETERS
numArgs="$#"
if [[ $numArgs == 0 ]]; then
	echo "incorrect num args: got $numArgs, expected 5"
	exit 1
fi

help () {
    echo "This script runs npm-chaos.sh in a docker container for a given kube config."
	echo "Currently it requires you specify a capture option i.e. -c or -m."
	echo "For more info, run npm.chaos.sh -h"
    echo
    echo "Usage:"
    echo "./npm-chaos-in-docker.sh -f <kube-config-name> [-d] -n <experiment-name> -c|-m <other-chaos-args...>"
    echo "-h"
    echo "    Print this help message."
    echo "Docker args:"
	echo "    -f"
	echo "        The file name of the kube config file to use. Must be the first arg. This file should be in the following directory: $localKubeConfigFolder"
	echo "    -d"
	echo "        Delete and create a new container if it already exists."
    echo "Chaos args (must be specified last):"
    echo "    -n <experiment-name>"
    echo "        Specify an experiment name. Default is 'experiment'."
    echo "    -m"
    echo "        Capture pprof memory. Currently must specify one of -m or -c."
    echo "    -c"
    echo "        Capture pprof cpu. Currently must specify one of -m or -c."
    echo "    <other-chaos-args...>"
    echo "        Any other chaos args to pass to npm-chaos.sh. These args must come last."
}

if [[ "$#" == 0 ]]; then
    help
    exit 1
fi

while getopts ":f:dn:mch" option; do
    case $option in
        f)
            kubeConfigName=$OPTARG;;
        d)
            shouldDeleteExistingContainer=true;;
        n)
            experimentName=$OPTARG;;
        m)
            if [[ $haveCaptureMode == "true" ]]; then
                echo "You can only specify one capture mode."
                exit 1
            fi
            haveCaptureMode=true
            captureMode="memory";;
        c)
            if [[ $haveCaptureMode == "true" ]]; then
                echo "You can only specify one capture mode."
                exit 1
            fi
            haveCaptureMode=true
            captureMode="cpu";;
        h)
            help
            exit 0;;
   esac
done

if [[ -z $kubeConfigName ]]; then
	echo "kube config file name is required"
	exit 1
fi
if [[ -z $captureMode ]]; then
	echo "capture mode (either -m or -c) is currently a required chaos arg for this script"
	exit 1
fi
if [[ $shouldDeleteExistingContainer != "true" ]]; then
    shouldDeleteExistingContainer=false
fi

## shift the args to the chaos args
if [[ $1 != "-f" ]]; then
    echo "-f must be the first option"
    exit 1
fi
if [[ $shouldDeleteExistingContainer == "true" ]]; then
    if [[ $3 != "-d" ]]; then
        echo "-d must be the second option"
        exit 1
    fi
    shift 3
else
    shift 2
fi

## finish setup
localConfigFile=$localKubeConfigFolder/$kubeConfigName
containerName=$kubeConfigName
resultsFolderSuffix=npm-chaos-results/$experimentName/$captureMode
# results folder needs to be outside the repo so we don't copy it to the docker container
localResultsFolder=~/$resultsFolderSuffix
dockerResultsFolder=/$resultsFolderSuffix

## display and write config to file
set -x
set -e
mkdir -p $localResultsFolder
set +e
set +x
cat > $localResultsFolder/docker-parameters.txt << EOF
Running NPM Chaos in a docker container with the following config:
kube config file: $localConfigFile
delete existing container: $shouldDeleteExistingContainer
chaos args: $@

Using the following constants/derived values:
dockerImage: $dockerImage
containerName: $containerName
localConfigFile: $localConfigFile
localResultsFolder: $localResultsFolder
dockerResultsFolder: $dockerResultsFolder

Using the following constants:
dockerImage: $dockerImage

EOF

cat $localResultsFolder/docker-parameters.txt

## BEGIN SCRIPT
set -x
docker images | grep $dockerImage || exit_code=$?
if [[ $exit_code -ne 0 ]]; then
    echo "Build the image since it does not exist."
    docker build -t $dockerImage -f k8s-and-go.Dockerfile .
fi

## create and setup a container with the kube config
docker ps | grep ${containerName} || exit_code=$?
if [[ $exit_code -eq 0 ]]; then
	echo "docker container $containerName already exists for this kube config."
	if [[ $shouldDeleteExistingContainer == "true" ]]; then
		echo "deleting the old container and creating a new one."
		docker stop $containerName && docker rm $containerName
	else
		echo "NOT running the experiment. To delete an existing container and create new one, use -d."
		exit 1
	fi
fi

set -e # fail the script if any setup for the docker environment fails
docker run -it -d --name $containerName $dockerImage
docker exec $containerName mkdir -p $dockerBaseFolder
# copy the repo over to the container
docker cp ./ $containerName:$dockerBaseFolder/
dockerKubeFolder=/root/.kube
docker exec $containerName mkdir -p $dockerKubeFolder
docker cp $localConfigFile $containerName:$dockerKubeFolder/config
docker exec $containerName chmod +x $dockerChaosFile

## run the experiment
set +e
echo "starting experiment and writing results to $localResultsFolder/docker-exec.out"
docker exec -it $containerName $dockerChaosFile "$@" > $localResultsFolder/docker-exec.out
echo "Finished running experiment. Printing out command line output:"
echo "BEGIN EXPERIMENT OUTPUT"
cat $localResultsFolder/docker-exec.out
echo "END EXPERIMENT OUTPUT"
echo "copying results to $localResultsFolder"
docker cp $containerName:$dockerResultsFolder/. $localResultsFolder/

