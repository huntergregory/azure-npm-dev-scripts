round=1
while : ; do
    echo "round $round: collecting node metrics at $(date)"
    kubectl top node
    echo "round $round: collected node metrics at $(date)"
    sleep 5s
    echo "round $round: collecting pod status at $(date)"
    kubectl get pod -owide -A
    echo "round $round: collected pod status at $(date)"
    echo "sleeping 5m"
    echo

    sleep 5m
    round=$((round+1))
done
