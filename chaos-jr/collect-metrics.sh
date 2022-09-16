if [[ $1 == "" ]]; then
  echo "specify the kube config file as first arg"
  exit 1
fi

round=1
while : ; do
    echo "round $round: collecting node metrics at $(date)"
    kubectl top node --kubeconfig $1
    echo "round $round: collected node metrics at $(date)"
    sleep 5s
    echo "round $round: collecting pod status at $(date)"
    kubectl get pod -owide -A --kubeconfig $1
    echo "round $round: collected pod status at $(date)"
    echo "sleeping 1m"
    echo

    sleep 1m
    round=$((round+1))
done
