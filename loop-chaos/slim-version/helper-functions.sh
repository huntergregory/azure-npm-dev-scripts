testAllowFromBTo() {
    toPod=$1
    MAX_TRIES=15 # at most 1m30s (6s * 15)
    startTime=`date`
    startTimeSeconds=`date +%s`
    try=1
    echo "waiting until b to $toPod is allowed..."
    while [[ $try -le $MAX_TRIES ]]; do
        rc=0; kubectl exec -n loop-chaos b -- /agnhost connect --timeout=3s --protocol=tcp s-$toPod.loop-chaos.svc.cluster.local:80 || rc=$?
        if [[ $rc == 0 ]]; then
            endTimeSeconds=`date +%s`
            diff=$(echo "$endTimeSeconds-$startTimeSeconds" | bc)
            echo "Achieved desired allow to $toPod after $diff seconds."
            return 0
        fi
        sleep 3s
        try=$(($try + 1))
    done

    diff=$(echo "$endTimeSeconds-$startTimeSeconds" | bc)
    echo "ERROR: never saw b to $toPod allowed after $diff seconds"
    return 1
}

testBlockFromBTo() {
    toPod=$1
    MAX_TRIES=30 # at most 1m30s (3s * 30)
    startTime=`date`
    startTimeSeconds=`date +%s`
    try=1
    echo "waiting until b to $toPod is blocked..."
    while [[ $try -le $MAX_TRIES ]]; do
        rc=0; kubectl exec -n loop-chaos b -- /agnhost connect --timeout=3s --protocol=tcp s-$toPod.loop-chaos.svc.cluster.local:80 || rc=$?
        if [[ $rc == 1 ]]; then
            endTimeSeconds=`date +%s`
            diff=$(echo "$endTimeSeconds-$startTimeSeconds" | bc)
            echo "Achieved desired block to $toPod after $diff seconds."
            return 0
        fi
        sleep 3s
        try=$(($try + 1))
    done

    diff=$(echo "$endTimeSeconds-$startTimeSeconds" | bc)
    echo "ERROR: never saw a to $toPod blocked after $diff seconds"
    return 1
}