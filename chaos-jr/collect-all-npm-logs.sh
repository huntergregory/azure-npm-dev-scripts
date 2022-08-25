if [[ $1 == "" ]]; then
  echo "specify the kube config file as first arg"
  exit 1
fi

set -x
npmPods=`kubectl get pod -n kube-system | grep npm | awk '{print $1}'`
for pod in $npmPods; do
    logFilePath="$1/$pod.log"
    echo "Saving npm logs to $logFilePath in a background process"
    kubectl logs -n kube-system -f $pod --kubeconfig=$1 > $logFilePath &
done
