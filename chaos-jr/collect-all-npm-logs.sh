if [[ $1 == "" ]]; then
  echo "specify the kube config file as first arg"
  exit 1
fi

if [[ $2 == "" ]]; then
  echo "specify the full path to the output folder (without a trailing slash)"
  exit 1
fi

set -x
npmPods=`kubectl --kubeconfig $1 get pod -n kube-system | grep npm | awk '{print $1}'`
mkdir -p $2
for pod in $npmPods; do
    logFilePath="$2/$pod.log"
    echo "Saving npm logs to $logFilePath in a background process"
    kubectl --kubeconfig $1 logs -n kube-system -f $pod --kubeconfig=$1 > $logFilePath &
done
