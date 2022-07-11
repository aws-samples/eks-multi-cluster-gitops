# Multi-cluster GitOps Scripts

## Workload cluster management

### init-workload-cluster.sh

Usage:
```
init-workload-cluster.sh <cluster_name> <gitops_system_path> <gitops_workloads_path>
```

Updates the local and remote repos for `gitops-system` and `gitops-workloads` to add a new workload cluster.
This is achieved by copying the required template folders into new folders for the cluster to be added.

Note that this script does not create the new cluster, as the `kustomization.yaml` file in `clusters-config` is not
updated. To create the cluster, you need to follow the repo initialization with `create-workload-cluster.sh`.


### create-workload-cluster.sh

Usage:
```
init-workload-cluster.sh <cluster_name> <gitops_system_path>
```

Creates a previously initialized cluster by updating `cluster-configs/kustomization.yaml`. This causes flux to pick up the
configuration of the cluster, which is then created by crossplane.

### delete-workload-cluster.sh

Usage:
```
delete-workload-cluster.sh <cluster_name> <gitops_system_path>
```

This does the reverse of `init-workload-cluster.sh`. It removes the specified cluster from `cluster-configs/kustomization.yaml`. This triggers crossplane to remove the cluster.

### cleanup-workload-cluster.sh

Usage:
```
cleanup-workload-cluster.sh <cluster_name> <gitops_system_path>
```

Once a cluster has been deleted you can use this script to remove all cluster configuration files from the local
and remote repos.

## Add application to Workload cluster

** WORK IN PROGRESS **

### add-cluster-overlay


### add-app-to-cluster <cluster_name> <app> <secret>

Steps to include:
- Create sealed secret
- Update repos
