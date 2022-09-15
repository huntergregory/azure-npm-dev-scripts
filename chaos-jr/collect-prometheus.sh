if [[ $1 == "" ]]; then
  echo "specify the kube config file as first arg"
  exit 1
fi

if [[ $2 == "" ]]; then
  echo "specify the directory as second arg"
  exit 1
fi

baseDir=prometheus-results-$1/$2
# test -d prometheus-results-$1/$2 && echo "dir prometheus-results-$1/$2 already exists" && exit 1
mkdir -p prometheus-results-$1/$2

round=1
npmPods=`kubectl --kubeconfig=$1 get pod -n kube-system | grep npm-win | awk '{ print $1 }'`
npmLinuxPods=`kubectl --kubeconfig=$1 get pod -n kube-system | grep npm | grep -v npm-win | awk '{ print $1 }'`
while : ; do
    for npmPod in $npmLinuxPods; do
        mkdir -p $baseDir/$npmPod/
        echo "round $round: collecting metrics for $npmPod at $(date)"
        dateString=`date | awk '{print $2 "-" $3 "-" $4}' | tr ':' '-'`
        echo date string: $dateString
        kubectl --kubeconfig=$1 exec -it $npmPod -n kube-system -- bash -c "apt-get update && apt-get install curl -y"
        kubectl --kubeconfig=$1 exec -it $npmPod -n kube-system -- curl localhost:10091/cluster-metrics > $baseDir/$npmPod/${dateString}cluster-metrics.txt
        kubectl --kubeconfig=$1 exec -it $npmPod -n kube-system -- curl localhost:10091/node-metrics > $baseDir/$npmPod/${dateString}node-metrics.txt
        echo "round $round: collected metrics for $npmPod at $(date)"
        echo "sleeping 5s"
        sleep 5s
    done
    echo "CAPTURED ALL LINUX"

    for npmPod in $npmPods; do
        mkdir -p $baseDir/$npmPod/
        echo "round $round: collecting metrics for $npmPod at $(date)"
        dateString=`date | awk '{print $2 "-" $3 "-" $4}' | tr ':' '-'`
        echo date string: $dateString
        kubectl --kubeconfig=$1 exec -it $npmPod -n kube-system -- powershell.exe curl http://localhost:10091/cluster-metrics -useBasicParsing -outFile cluster-metrics.txt
        kubectl --kubeconfig=$1 exec -it $npmPod -n kube-system -- powershell.exe curl http://localhost:10091/node-metrics -useBasicParsing -outFile node-metrics.txt
        kubectl --kubeconfig=$1 cp -n kube-system $npmPod:cluster-metrics.txt $baseDir/$npmPod/${dateString}cluster-metrics.txt
        kubectl --kubeconfig=$1 cp -n kube-system $npmPod:node-metrics.txt $baseDir/$npmPod/${dateString}node-metrics.txt
        echo "round $round: collected metrics for $npmPod at $(date)"
        echo "sleeping 5s"
        sleep 5s
    done

    echo "CAPTURED ALL WINDOWS. sleeping 5m"
    sleep 5m
    round=$((round+1))
done
