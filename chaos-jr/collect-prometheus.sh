if [[ $1 == "" ]]; then
  echo "specify the kube config file as first arg"
  exit 1
fi

if [[ $2 == "" ]]; then
  echo "specify the directory as second arg"
  exit 1
fi

baseDir=prometheus-results-$1/$2
test -d prometheus-results-$1/$2 && echo "dir already exists" && exit 1
mkdir -p prometheus-results-$1/$2

round=1
npmPods=`kubectl get pod -n kube-system | grep npm-win | awk '{ print $1 }'`
while : ; do
    for npmPod in $npmPods; do
        mkdir -p $baseDir/$npmPod/
        echo "round $round: collecting metrics for $npmPod at $(date)"
        dateString=
        for i in `date | awk '{print $4}' | tr ':' ' '`; do dateString=$dateString$i- ; done
        echo "dateString: $dateString"
        kubectl exec -it $npmPod -n kube-system -- powershell.exe curl http://localhost:10091/cluster-metrics -useBasicParsing -outFile cluster-metrics.txt
        kubectl exec -it $npmPod -n kube-system -- powershell.exe curl http://localhost:10091/node-metrics -useBasicParsing -outFile node-metrics.txt
        kubectl cp -n kube-system $npmPod:cluster-metrics.txt $baseDir/$npmPod/${dateString}cluster-metrics.txt
        kubectl cp -n kube-system $npmPod:node-metrics.txt $baseDir/$npmPod/${dateString}node-metrics.txt
        echo "round $round: collected metrics for $npmPod at $(date)"
        echo "sleeping 5s"
        sleep 5s
    done

    echo "CAPTURED ALL. sleeping 20m"
    sleep 20m
    round=$((round+1))
done
