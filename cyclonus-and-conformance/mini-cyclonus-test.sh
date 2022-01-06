#!/bin/bash

## NOTE must be called with sudo for ipset/iptables to work if there's an unexpected result
MAX_ROUNDS=10

help () {
	echo "Run a cyclonus test using a given network policy and test config."
	echo
	echo "Usage:"
	echo "./mini-cyclonus-test.sh <netpol-file> <test-config-file> [-s] [-d]"
	echo
    echo "-s"
    echo "    Skip deletion of namespaces and installation of test matrix."
    echo "-d"
    echo "    Show debug output from testing connections."
	echo "-h"
	echo "    Print this help message"
}

if [[ $# < 2 ]]; then
	help
	exit 1
fi

netpolFile=$1
testConfigFile=$2

shift 2

shouldHideConnectionOutput=true
shouldSkipInstall=false
while getopts ":sdh" option; do
    case $option in
		s)
			shouldSkipInstall=true;;
        d)
            shouldHideConnectionOutput=false;;
		h)
			help
			exit 0;;
		\?)
			echo "Invalid option: -$OPTARG" >&2
			exit 1;;
	esac
done

set -x
sudo echo "get root access for ipset/iptables if needed later (use ctrl + C to deny and continue)"
set +x

if [[ $shouldSkipInstall == false ]]; then
    echo "Deleting existing test namespaces..."
    kubectl delete ns x y z
    echo "Installing test matrix..."
    kubectl apply -f test-agnhost-matrix.yaml
fi

kubectl apply -f $netpolFile

# loop through lines of test file and make sure the connection is as expected
echo "Testing mini cyclonus test for $MAX_ROUNDS rounds..."
for i in $( seq 1 $MAX_ROUNDS ); do
    echo "Round $i"
    
    while read -r line; do
        if [[ -z $line ]]; then
            continue
        fi
        srcNS=$(echo $line | cut -d' ' -f1)
        srcPod=$(echo $line | cut -d' ' -f2)
        dstNS=$(echo $line | cut -d' ' -f3)
        dstPod=$(echo $line | cut -d' ' -f4)
        port=$(echo $line | cut -d' ' -f5)
        protocol=$(echo $line | cut -d' ' -f6)
        expected=$(echo $line | cut -d' ' -f7)
        expectedCode=0
        if [[ $expected == "X" ]]; then
            expectedCode=1
        fi
        
        if [[ $shouldHideConnectionOutput == true ]]; then
            ./connect-agnhosts.sh $srcNS $srcPod $dstNS $dstPod -r $port -p $protocol > /dev/null 2>&1 # suppress stdout and stderr (send it to the null device)
        else
            ./connect-agnhosts.sh $srcNS $srcPod $dstNS $dstPod -r $port -p $protocol
        fi
        exitCode=$?
        if [[ $exitCode != $expectedCode ]]; then
            echo "IPTABLES LIST OUTPUT"
            sudo iptables -L -n
            echo
            echo "IPSET LIST OUTPUT"
            sudo ipset -L
            echo
            echo "Got unexpected result for $srcNS/$srcPod to $dstNS/$dstPod via $protocol on port $port."
            if [[ $exitCode == 0 ]]; then
                echo "Expected connection failure, but got success."
            else
                echo "Expected a successful connection, but got failure."
            fi
            exit 1
        fi
    done < $testConfigFile
done
echo "Success across $MAX_ROUNDS rounds of tests."
