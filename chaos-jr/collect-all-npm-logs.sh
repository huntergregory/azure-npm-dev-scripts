if [[ $1 == "" ]]; then
  echo "specify the kube config file as first arg"
  exit 1
fi

npmPods=`kubectl get pod -n kube-system | grep npm | awk '{print $1}'`
for pod in $npmPods; do
    logFilePath="$pod.log"
    echo "Saving npm logs to $logFilePath in a background process"
    kubectl --kubeconfig=$1 logs -n kube-system $npmPod -f > $logFilePath &
done
