NUM_ROUNDS=30
POLICY_FILE=policy-ingress-access-from-updated-pod.yaml
dateString=`date -I`-`date | awk '{print $4}'` # like 2022-09-24-15:45:03
RESULTS_FOLDER=loop-results/$dateString

test -d $RESULTS_FOLDER
if [[ $? -eq 0 ]]; then
    echo "results folder already exists: $RESULTS_FOLDER"
    exit 1
fi

mkdir -p $RESULTS_FOLDER
RESULTS_FILE=$RESULTS_FOLDER/modify-loop-results.txt
echo "RESULTS_FILE: $RESULTS_FILE" | tee -a $RESULTS_FILE
echo "NUM_ROUNDS: $NUM_ROUNDS" | tee -a $RESULTS_FILE
echo "POLICY_FILE: $POLICY_FILE" | tee -a $RESULTS_FILE

exitOnSetupFailure() {
    exitCode=$1
    if [[ $exitCode -ne 0 ]]; then
        rm $RESULTS_FILE
        rmdir $RESULTS_FOLDER
        exit $exitCode
    fi
}

# SETUP
echo "cleaning up old x namespace..."
kubectl delete ns x
# kubectl delete netpol -n x --all
# kubectl label pod -n x b pod2-

kubectl create ns x
kubectl apply -n x -f test-3-minimal-agnhost-pods.yaml
echo "NOTE: make sure the nodes of your choice are labeled with vm=0, vm=1, and vm=2"
echo "waiting for x/a, x/b, x/c to be running..."
kubectl wait pod -n x a b c --for condition=ready --timeout=600s
exitOnSetupFailure $?

# echo "WILL RESTART NPM. Cancel now to comment out restart..."
# echo 5... && sleep 1 && echo 4... && sleep 1 && echo 3... && sleep 1 && echo 2... && sleep 1 && echo 1... && sleep 1
# echo "restarting npm-win..."
# kubectl rollout restart ds -n kube-system azure-npm-win
# echo "sleeping 2m"
# sleep 2m

xaNode=`kubectl get pod -o template -n x a --template={{.spec.nodeName}}`
npmPod=`kubectl get pod -n kube-system -owide | grep azure-npm | grep $xaNode | awk '{print $1}'`
echo "npmPod: $npmPod"
if [[ $npmPod == "" ]]; then
    echo "couldn't find npmPod on x/a's node: $xaNode"
    exitOnSetupFailure 1
fi

# BEGIN
scriptStart=`date`
backgroundFile=$RESULTS_FOLDER/$npmPod-background.log
echo "beginning script at $scriptStart" | tee -a $RESULTS_FILE
echo "writing log of $npmPod to background at $backgroundFile" | tee -a $RESULTS_FILE
kubectl logs -n kube-system $npmPod -f > $backgroundFile &
logPID=$!

finishScript() {
    finalFile=$RESULTS_FOLDER/$npmPod-final.log
    echo "finished script at $(date)" | tee -a $RESULTS_FILE
    echo "writing log of $npmPod at $finalFile" | tee -a $RESULTS_FILE
    kubectl logs -n kube-system $npmPod > $finalFile
    kill $logPID
}

blankLine() {
    echo | tee -a $RESULTS_FILE
}

verifyConnectivityFrom() {
    fromPod=$1
    echo "verifying connectivity from x/$fromPod to x/a..." | tee -a $RESULTS_FILE
    ../cyclonus-and-conformance/connect-agnhosts.sh x $fromPod x a > /dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        echo "FAILURE: broken connectivity from x/$fromPod to x/a. exiting..." | tee -a $RESULTS_FILE
        blankLine
        finishScript
        exit 1
    fi
    echo "good connectivity"
    blankLine
}

testAllow() {
    echo "waiting until x/b to x/a is allowed..." | tee -a $RESULTS_FILE
    ../cyclonus-and-conformance/connect-until.sh x b x a ALLOW >> $RESULTS_FILE
    if [[ $? -ne 0 ]]; then
        echo "FAILURE: never saw connectivity from x/b to x/a. Seeing if we can still connect from x/c to x/a" | tee -a $RESULTS_FILE
        verifyConnectivityFrom c
        finishScript
        exit 1
    fi
    blankLine
}

testBlock() {
    echo "waiting until x/b to x/a is blocked..." | tee -a $RESULTS_FILE
    ../cyclonus-and-conformance/connect-until.sh x b x a BLOCK >> $RESULTS_FILE
    if [[ $? -ne 0 ]]; then
        echo "FAILURE: never saw traffic denied from x/b to x/a"
        finishScript
        exit 1
    fi
    blankLine
}

verifyConnectivityFrom b
verifyConnectivityFrom c

round=1
while [[ $round -le $NUM_ROUNDS ]]; do
    echo "beginning round $round at $(date). Started at $scriptStart" | tee -a $RESULTS_FILE

    echo "adding policy..." | tee -a $RESULTS_FILE
    kubectl apply -n x -f $POLICY_FILE
    testBlock

    echo "labeling x/b..." | tee -a $RESULTS_FILE
    kubectl label pod -n x b pod2=updated
    testAllow

    echo "removing label..." | tee -a $RESULTS_FILE
    kubectl label pod -n x b pod2-
    testBlock

    echo "deleting policy..." | tee -a $RESULTS_FILE
    kubectl delete -n x -f $POLICY_FILE
    testAllow

    echo "finished round $round" | tee -a $RESULTS_FILE
    blankLine
    round=$(($round + 1))
done

finishScript
