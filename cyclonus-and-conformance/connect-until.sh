#!/bin/bash
## FIXME udp doesn't work even though it works for cyclonus testing (see logs)

PRINT_RESULT=true

help () {
	echo "Connect from one agnhost container to another's service."
	echo "The container cont-80-tcp must exist on the source pod."
	echo
	echo "Usage:"
	echo "./connect-agnhosts.sh <srcNS> <srcPod> <dstNS> <dstPod> BLOCK|ALLOW [-r <port>] [-p <protocol>] [-x]"
	echo
	echo "BLOCK|ALLOW: wait until traffic is either blocked or allowed"
	echo
	echo "-r <port>"
	echo "    Default is 80."
	echo "-p <protocol>"
	echo "    Default is tcp. UDP doesn't work right now."
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
blockOrAllow=$5
if [[ $blockOrAllow == "BLOCK" ]]; then
	desiredExitCode=1
elif [[ $blockOrAllow == "ALLOW" ]]; then
	desiredExitCode=0
else
	echo "Invalid exit code: $5"
	exit 1
fi
shift 5
while getopts ":p:r:xh" option; do
    case $option in
		r)
			port=$OPTARG;;
		p)
			protocol=$OPTARG;;
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
svcName=s-$dstPod # "s-$dstNS-$dstPod"
svcURL=$svcName.$dstNS.svc.cluster.local:$port

MAX_ROUNDS=$((12 * 5)) # 3 minutes
echo "max rounds: $MAX_ROUNDS"
echo "testing connectivity from $srcNS/$srcPod to $dstNS/$dstPod via $protocol on port $port."
startTime=`date`
startTimeSeconds=`date +%s`
echo "start time: $startTime"
round=1
while [[ $round -le $MAX_ROUNDS ]];
do
	# set -x
	kubectl exec -n $srcNS $srcPod -c $container -- /agnhost connect $svcURL --timeout=3s --protocol=$protocol
	exitCode=$?
	# set +x
	if [[ $exitCode == $desiredExitCode ]]; then
		endTimeSeconds=`date +%s`
		diff=$(echo "$endTimeSeconds-$startTimeSeconds" | bc)
		echo "Achieved desired ALLOW or BLOCK."
		echo "start time: $startTime"
		echo "end time: $(date)"
		echo "difference: $diff"
		exit 0
	fi
	echo "sleeping 3 seconds after round $round"
	sleep 3
	round=$(($round + 1))
done

echo "failed to achieve desired $blockOrAllow after $round tries" # block/allow
exit 1
