#!/bin/bash
## FIXME udp doesn't work even though it works for cyclonus testing (see logs)

PRINT_RESULT=true

help () {
	echo "Connect from one agnhost container to another's service."
	echo "The container cont-80-tcp must exist on the source pod."
	echo
	echo "Usage:"
	echo "./connect-agnhosts.sh srcNS srcPod dstNS dstPod [-r <port>] [-p <protocol>] [-k <kubeconfig>] [-x]"
	echo
	echo "-r <port>"
	echo "    Default is 80."
	echo "-p <protocol>"
	echo "    Default is tcp. UDP doesn't work right now."
	echo "-k <kubeconfig>"
	echo "    Default is ~/.kube/config"
	echo "-x"
	echo "    Show execution commands."
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
while getopts ":p:r:k:xh" option; do
    case $option in
		r)
			port=$OPTARG;;
		p)
			protocol=$OPTARG;;
		k)
			kubeconfig=$OPTARG;;
		x)
			set -x;;
		h)
			help
			exit 0;;
		\?)
			echo "Invalid option: -$OPTARG" >&2
			exit 1;;
	esac
done

if [[ -z $port ]]; then
	port=80
fi
if [[ -z $protocol ]]; then
	protocol="tcp"
fi

container="cont-80-tcp"
svcName="s-$dstNS-$dstPod"
configFile=~/.kube/config
if [[ $kubeconfig != "" ]]; then
	configFile=$kubeconfig
	svcName="s-$dstPod"
fi
svcURL=$svcName.$dstNS.svc.cluster.local:$port
kubectl --kubeconfig $configFile exec -n $srcNS $srcPod -c $container -- /agnhost connect $svcURL --timeout=5s --protocol=$protocol

exitCode=$?
set +x
if [[ $PRINT_RESULT == true ]]; then
	fromString="from $srcNS/$srcPod to $dstNS/$dstPod via $protocol on port $port."
	if [[ $exitCode == 0 ]]; then
		echo "Successfully connected $fromString"
	else
		echo "Connection failed $fromString"
	fi
fi

exit $exitCode
