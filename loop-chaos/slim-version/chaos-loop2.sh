##########################################################################################
# Scenario: 
# Perform multiple ACL operations and test connectivity from a 
# longstanding pod (b) to an ephemeral pod (a).
# 
# Includes longstanding NetPol.
# 1. Create Pod that does NOT satisfy the policy. Verify that traffic is allowed.
# 2. Add label to Pod, satisfying policy. Verify that traffic is blocked.
# 3. Remove label from Pod, no longer satisfying policy. Verify that traffic is allowed.
# 4. Repeat steps 2 and 3 multiple times.
# 5. Delete Pod.
#
# Repeat the above for multiple Pods.
##########################################################################################

NUM_ROUNDS=10

# fail script if any command fails
set -e

source ./helper-functions.sh

kubectl delete ns loop-chaos --ignore-not-found
kubectl create ns loop-chaos
kubectl apply -f yamls/pod-b.yaml

echo "waiting until pod b is running..."
kubectl wait --for=condition=Ready pod -n loop-chaos b --timeout=120s

echo "creating policy..."
kubectl apply -n loop-chaos -f yamls/allow-some-to-selected.yaml

round=1
while [[ $round -le $NUM_ROUNDS ]]; do
    echo "round $round: beginning at $(date)"

    echo "round $round: creating pod a that does not satisfy NetPol..."
    kubectl apply -f yamls/pod-a-no-selected.yaml
    echo "sleeping 1m30s for NPM/HNS to process everything (and pod a to come up)..."
    sleep 90s
    testAllowFromBTo a

    for i in {1..3}; do
        echo "round $round: time $i adding label to pod a (satisfying NetPol)..."
        kubectl label pod -n loop-chaos a selected=true
        testBlockFromBTo a

        echo "round $round: time $i removing label from pod a (no longer satisfying NetPol)..."
        kubectl label pod -n loop-chaos a selected-
        testAllowFromBTo a        
    done

    echo "round $round: deleting pod a..."
    kubectl delete pod -n loop-chaos a

    echo "round $round: finished at $(date)"
    echo
    round=$(($round + 1))
done
