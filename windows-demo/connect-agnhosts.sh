srcNS=$1
srcPod=$2
dstIP=$3

echo "Trying to connect from $srcNS/$srcPod to $dstIP on TCP port 80."

set -x
kubectl exec -n $srcNS $srcPod -c cont-80-tcp -- /agnhost connect $dstIP:80 --timeout=3s --protocol=tcp
exitCode=$?
set +x

if [[ $exitCode == 0 ]]; then
    echo "Successfully connected."
else
    echo "Connection failed."
fi
