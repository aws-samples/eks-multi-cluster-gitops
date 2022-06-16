
## Bootstrap the management cluster (using AWS CodeCommit repos)

1. Bootstrap Flux on the management cluster with the `mgmt` cluster config path. The bootstrap process is customized to support AWS CodeCommit integration.

```bash
export CLUSTER_NAME=mgmt

cd ~/environment/gitops-system

kubectl apply -f ./clusters/${CLUSTER_NAME}/flux-system/gotk-components.yaml

kubectl create secret generic flux-system -n flux-system \
    --from-file=identity=${HOME}/.ssh/gitops \
    --from-file=identity.pub=${HOME}/.ssh/gitops.pub \
    --from-file=known_hosts=${HOME}/.ssh/codecommit_known_hosts

kubectl apply -f ./clusters/${CLUSTER_NAME}/flux-system/gotk-sync.yaml
```

3. Wait for the `staging` cluster to start. Track the progress of the Flux
   deployments using the Flux CLI. This may take >30 minutes due to exponential
   backoff, however this is only a one-time process.
```bash
flux get all
```
You can watch this to see once it's ready by using:
```bash
watch -n 30 -d flux get all
```