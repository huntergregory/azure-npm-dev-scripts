#!/bin/bash
numDeployments=10
numNetpolsPerDeployment=2

echo "creating $numDeployments deployments and $numNetpolsPerDeployment netpols per deployment"

mkdir -p deployments
mkdir -p netpols
rm deployments/deployment*.yaml
rm netpols/netpol*.yaml

for (( i=1; i<=$numDeployments; i++ )); do
    ## generate deployment yaml
    toFile=deployments/deployment-$i.yaml
    sed "s/nameReplace/test-deployment-$i/g" example-deployment.yaml > $toFile
    sed -i "s/nsReplace/test-ns-$i/g" $toFile
    sed -i "s/labelReplace/label-$i/g" $toFile

    ## generate all netpols for this deployment
    for (( j=1; j<=$numNetpolsPerDeployment; j++ )); do
        toFile=netpols/netpol-$i-$j.yaml
        sed "s/nameReplace/test-netpol-$i-$j/g" example-netpol.yaml > $toFile
        sed -i "s/nsReplace/test-ns-$i/g" $toFile
        sed -i "s/labelReplace1/label-$i/g" $toFile
        z=$(( i + (j-1)*2 ))
        plus1=$(( z % numDeployments + 1))
        sed -i "s/labelReplace2/label-$plus1/g" $toFile
        plus2=$(( (z+1) % numDeployments + 1))
        sed -i "s/labelReplace3/label-$plus2/g" $toFile
    done
done

echo "done"
