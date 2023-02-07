##########################################################################################
# Scenario: 
# Perform multiple ACL operations and test connectivity from one longstanding pod (b)
# to another (a). Also test connectivity from b to an ephemeral pod (a2).
# 
# 1. Apply policy that pod a satisfies. Verify that traffic is blocked.
# 2. Create pod a2 that satisfies policy. Verify that traffic is blocked.
# 3. Label pod b so that it's allowed. Verify that traffic is allowed to both a and a2.
# 4. Delete pod a2.
# 5. Remove label from pod b so that it's blocked. Verify that traffic is blocked.
# 6. Delete policy. Verify that traffic is allowed.
#
# Repeat the above multiple times.
##########################################################################################

NUM_ROUNDS=10

# fail script if any command fails
set -e

source ./helper-functions.sh

kubectl delete ns loop-chaos --ignore-not-found
kubectl create ns loop-chaos
kubectl apply -f yamls/pod-a.yaml
kubectl apply -f yamls/pod-b.yaml
echo "waiting until pod a and b are running..."
kubectl wait --for=condition=Ready pod -n loop-chaos --all --timeout=120s

echo "verifying that b can connect to a at start..."
testAllowFromBTo a
echo "able to connect from b to a at start"

round=1
while [[ $round -le $NUM_ROUNDS ]]; do
    echo "round $round: beginning at $(date)"
    echo "round $round: adding policy..."
    kubectl apply -n loop-chaos -f yamls/allow-some-to-selected.yaml
    testBlockFromBTo a

    echo "round $round: creating new pod that satisfies policy..."
    kubectl apply -f yamls/pod-a2.yaml
    kubectl wait --for=condition=Ready pod -n loop-chaos a2 --timeout=120s
    testBlockFromBTo a2

    # need to make sure traffic to a2 would ever be allowed
    echo "round $round: labeling b so that it's allowed..."
    kubectl label pod -n loop-chaos b allowFrom=true
    echo "testing allow to both a and a2 in background..."
    # temporarily stop failing script if any command fails
    set +e
    testAllowFromBTo a &
    aPid=$!
    testAllowFromBTo a2 &
    a2Pid=$!
    aRC=0; wait $aPid || aRC=$?
    a2RC=0; wait $a2Pid || a2RC=$?
    if [[ $aRC != 0 ]] || [[ $a2RC != 0 ]]; then
        echo "ERROR: allow to a or a2 failed. aRC=$aRC, a2RC=$a2RC"
        exit 1
    fi
    set -e

    echo "round $round: deleting pod a2..."
    kubectl delete pod -n loop-chaos a2

    echo "round $round: removing label from b so that it's blocked..."
    kubectl label pod -n loop-chaos b allowFrom-
    testBlockFromBTo a

    echo "round $round: deleting policy..."
    kubectl delete -n loop-chaos -f yamls/allow-some-to-selected.yaml
    testAllowFromBTo a

    echo "round $round: finished at $(date)"
    echo
    round=$(($round + 1))
done
