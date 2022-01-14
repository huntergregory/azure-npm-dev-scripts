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
    echo "./cylconus-reliability.sh -f <kube-config-name> -n <experiment-name> -c <count> -i <npm-image> -p <npm-profile-name> [-d]"
	echo "-f"
	echo "    The file name of the kube config file to use."
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
while getopts ":f:n:c:i:p:dh" option; do
    case $option in
        f)
            kubeConfigFile=$OPTARG;;
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
   esac
done

if [[ -z $kubeConfigFile || -z $experimentName || -z $count || -z $image || -z $profile ]]; then
	echo "missing a required parameter"
	exit 1
fi

## finish setup
# results folder needs to be outside the repo so we don't copy it to the docker container
localResultsFolder=../../npm-cyclonus-reliability-results/$experimentName
dockerResultsFolder=/npm-cyclonus-results

## display and write config to file
set -ex
mkdir -p $localResultsFolder
set +ex
cat > $localResultsFolder/parameters.txt << EOF
Running NPM Chaos in a docker container with the following config:
kube config file: $kubeConfigFile
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
docker images | grep $dockerImage || exit_code=$?
if [[ $exit_code -ne 0 ]]; then
    echo "Build the image since it does not exist."
    docker build -t $dockerImage -f k8s-and-go.Dockerfile .
fi

for i in $( seq 1 $count ); do
    containerName=$experimentName$i
    echo "Starting round $i of $count. Creating container $containerName."

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

    set -e # fail the script if any setup for the docker environment fails
    docker run -it -d --name $containerName $dockerImage
    docker exec $containerName mkdir -p $dockerBaseFolder
    # copy the repo over to the container
    docker cp ../. $containerName:$dockerBaseFolder/
    dockerKubeFolder=/root/.kube
    docker exec $containerName mkdir -p $dockerKubeFolder
    docker cp $kubeConfigFile $containerName:$dockerKubeFolder/config
    docker exec $containerName chmod +x $dockerCyclonusFile
    set +e

    docker exec $containerName $dockerCyclonusFile -i $image -p $profile &
done

echo "WAITING FOR ALL CONTAINERS TO FINISH @ $(date)"
wait

for i in $( seq 1 $count ); do
    containerName=$experimentName$i
    folder=$localResultsFolder/container$i
    echo "Copying results from container $containerName to $folder."
    mkdir -p $folder
    docker cp $containerName:$dockerResultsFolder $folder
done
