Arguments:
- number of NetPols per deployment
- number of deployments per namespace
- number of namespaces
- number of replicas per deployment

Steps:
1. ./generate-yamls.sh (specify number of deployments and NetPols per deployment)
2. ./create-deployments.sh (specify number of namespaces to replicate everything to)
3. ./scale-deployments.sh (specify number of replicas per deployment)
4. ./create-netpols.sh
