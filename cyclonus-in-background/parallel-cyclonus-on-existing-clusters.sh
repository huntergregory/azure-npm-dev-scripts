clusters=("cluster-context1" "cluster-context2" "cluster-context3")
for cluster in ${clusters[*]}; do
    excluded="sctp,named-port,ip-block-with-except,multi-peer,upstream-e2e,example,end-port,namespaces-by-default-label,update-policy"
    ./cyclonus generate \
        --context $cluster \
        --noisy=true \
        --retries=7 \
        --ignore-loopback=true \
        --cleanup-namespaces=false \
        --perturbation-wait-seconds=20 \
        --pod-creation-timeout-seconds=1200 \
        --job-timeout-seconds=15 \
        --server-protocol=TCP,UDP \
        --exclude $excluded | tee $resultsFolder/$cluster.out &
done

wait

failed=false
for cluster in ${clusters[*]}; do
    rc=0
    cat $resultsFolder/$cluster.out | grep "failed" > /dev/null 2>&1 || rc=$?
    echo $rc
    if [ $rc -eq 0 ]; then
        echo "FAILURES detected in cluster $cluster"
        failed=true
    else
        echo "SUCCESSFUL run for cluster $cluster"
    fi
done

if [[ $failed == true ]]; then
    exit 1
fi
