#!/bin/bash
timeout=3

help () {
	echo "Ping from a pod to a pod (or its service)."
	echo
	echo "Usage:"
	echo "./ping-from-pod.sh srcNS srcPod dstNS dstPod [-s] [-m <mode>] [-r <port>] [-p <protocol>]"
	echo
	echo "-s"
    echo "    Skip installation of curl on the pod."
	echo "-m <mode>"
	echo "    The default mode is pod-ip. Possible mode values are:"
	echo "        - pod-ip"
	echo "        - svc-domain-name"
	echo "        - svc-cluster-ip"
	echo "        - svc-external-ip"
	echo "-r <port>"
	echo "-p <protocol>"
	echo "    Default is tcp. Currently no implementation for other protocols."
	echo "-h"
	echo "    Print this help message"
}

if [[ $# == 0 ]]; then
	help
	exit 1
fi
srcNS=$1
srcPod=$2
dstNS=$3
dstPod=$4
shift 4
while getopts ":m:p:r:sh" option; do
    case $option in
		s)
			shouldInstall=false;;
		m)
			mode=$OPTARG;;
		r)
			port=$OPTARG;;
		p)
			protocol=$OPTARG
			if [[ $protocol != "tcp" ]]; then
				echo "Currently no implementation for other protocols."
				exit 1
			fi;;
		h)
			help
			exit 0;;
		\?)
			echo "Invalid option: -$OPTARG" >&2
			exit 1;;
	esac
done

if [[ -z $shouldInstall ]]; then
	shouldInstall=true
fi
if [[ -z $mode ]]; then
	mode="pod-ip"
fi
if [[ -z $protocol ]]; then
	protocol="tcp"
fi

set -x
if [[ $shouldInstall == true ]]; then
	# run this in the background
	kubectl exec -it -n $srcNS $srcPod -- bash -c "apt-get update && apt-get install curl --yes" &
fi

svcName="s-$dstNS-$dstPod"

if [[ $mode == "pod-ip" ]]; then
	address=$(kubectl get -n $dstNS pod $dstPod -o jsonpath='{.status.podIP}')
elif [[ $mode == "svc-domain-name" ]]; then
	address="http://$svcName.$dstNS.svc.cluster.local"
elif [[ $mode == "svc-cluster-ip" ]]; then
	address=$(kubectl get -n $dstNS svc $svcName -o jsonpath='{.spec.clusterIP}')
elif [[ $mode == "svc-external-ip" ]]; then
	address=$(kubectl get -n $dstNS svc $svcName -o jsonpath='{.spec.externalIP}')
	if [[ -z $address ]]; then
		echo "can't run the experiment: no external IP address for this service"
		wait
		exit 1
	fi
else
	wait
	set +x
	echo
	help
	exit 1
fi

if [[ $port != "" ]]; then
	address="$address:$port"
fi

commandString="curl --connect-timeout $timeout $address"
wait
kubectl exec -it -n $srcNS $srcPod -- bash -c "$commandString"
