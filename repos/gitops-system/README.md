# GitOps System

This directory contains all of the manifests which define the GitOps systems for
the management cluster and each of the workload clusters. 

## Structure

### `clusters`

Stores the Flux entrypoint definitions for each of the clusters (including the
management cluster). Each of the subdirectories corresponds 1:1 with a cluster.
The `mgmt` cluster represents the management cluster, whereas all other clusters
are represented by their name. Within their respective subdirectory, each
cluster has a `flux-system` directory to store the Flux CD configuration
manifests (CRDs, Deployments, etc.) and also a reference to the `gitops-system`
manifest Git repository and a Kustomization for its own resources (which points
to the cluster subdirectory). You can think of this subdirectory as the
entrypoint for all of the other Flux CD Kustomizations and Helm Releases to be
deployed into the environment.

### `clusters-config`

Stores the cluster and tool configuration for each of the workload clusters. The
`def` subdirectory contains the EKS cluster definition, as represented by a
Crossplane custom resource (the XRD defined in `tools`). The `external-secrets`
subdirectory installs the External Secrets Helm chart. The `initialization`
subdirectory contains the `flux-system` namespace. This is required so that the
`Kustomization` which installs the tools into the cluster (External Secrets,
Flux CD) can depend on it to ensure that the Namespace exists. The `secrets`
subdirectory contains the secrets required by the local Flux CD installation to
connect to its workload and manifest Git repositories (sealed with the common
Sealed Secrets certificate). The other files in this directory install the tools
required by the cluster - [External Secrets][external-secrets], Flux, [Sealed
Secrets][sealed-secrets] - and their respective configurations.

[external-secrets]: https://github.com/external-secrets/external-secrets
[sealed-secrets]: https://github.com/bitnami-labs/sealed-secrets

### `tools`

Stores the configuration for any tools required by workload clusters. The
`crossplane` subdirectory contains the core [Crossplane][crossplane]
installation, configuration for the [Crossplane AWS Provider][crossplane-aws],
configuration for authenticating the AWS provider with credentials and
Crossplane composite resource definitions and compositions for an EKS cluster.
The `external-secrets` subdirectory contains a `HelmRelease` for installing the
External Secrets operator (used only by the management cluster).

[crossplane]: https://github.com/crossplane/crossplane
[crossplane-aws]: https://github.com/crossplane/provider-aws

### `tools-config`

Stores optional configuration for any tools required by the workload cluster.
Currently this directory only contains configuration for the common signing key
required by Sealed Secrets to decrypt each of the secrets.

### `workloads`

Stores the workload configuration manifests for each of the clusters. Each of
the subdirectories corresponds 1:1 with a workload cluster. Within their
respective subdirectory, each cluster has references to Git repositories and
Kustomizations for any of the workloads that should be installed into the
cluster.