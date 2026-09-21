# Requirements Document

## Introduction

The `eks-multi-cluster-gitops` sample implements a hub/spoke multi-cluster GitOps system on Amazon EKS using Flux CD for reconciliation and Crossplane for infrastructure provisioning. Every component in the solution is pinned to a version, and those pins have fallen substantially behind current releases. Several pins now reference versions that upstream projects have removed, deprecated, or never published, which means the end-to-end flow described in `initial-setup/README.md` and `scenarios.md` cannot complete against current upstream artifacts.

This feature upgrades every version-pinned component in the repository to its current supported release, migrates the manifests and configuration that the upgrades break, replaces a development environment platform that AWS has closed to new customers, keeps the bootstrap-to-workload-cluster flow functional, and brings the documentation back in line with what the repository actually deploys.

### Discovered version inventory

The following pins were found by scanning the repository. They are recorded here as the factual starting point for the upgrade; the authoritative, complete list is produced by Requirement 1.

**Bootstrap and tooling**

| Component | Location | Pinned version |
|---|---|---|
| Management cluster Kubernetes version | `initial-setup/config/mgmt-cluster-eksctl.yaml` | `1.29` |
| eksctl `ClusterConfig` API version | `initial-setup/config/mgmt-cluster-eksctl.yaml` | `eksctl.io/v1alpha5` |
| CloudFormation `KubernetesVersion` parameter | `initial-setup/auto/cfn.yaml` | default `1.29`, allowed `1.29`/`1.28`/`1.27` |
| `kubectl` download map | `initial-setup/auto/cfn.yaml` | `1.29.0`, `1.28.5`, `1.27.9` (release date `2024-01-04`) |
| Flux CLI | `initial-setup/auto/cfn.yaml` | `FLUX_VERSION=0.35.0` |
| `kubectl` download | `initial-setup/README.md` | `1.24.7` (release date `2022-10-31`) |
| `yq` | `initial-setup/README.md` | `v4.24.5` |
| `kubeseal` | `initial-setup/README.md` | `v0.19.4` |
| Development environment operating system | `initial-setup/README.md` | Ubuntu 18.04 |
| Development environment AMI parameter | `initial-setup/auto/cfn.yaml` | `Cloud9ImageId`, default `amazonlinux-2-x86_64`, allowed value `ubuntu-18.04-x86_64` — a pin that this feature removes together with the Cloud9 environment rather than upgrading |

**Flux**

| Component | Location | Pinned version |
|---|---|---|
| Flux distribution | `repos/gitops-system/clusters/{mgmt,template}/flux-system/gotk-components.yaml` | `v2.1.2` |
| source-controller | same | `v1.1.2` |
| kustomize-controller | same | `v1.1.1` |
| helm-controller | same | `v0.36.2` |
| notification-controller | same | `v1.1.0` |
| `Kustomization` API version | throughout `repos/` | `kustomize.toolkit.fluxcd.io/v1beta2` |
| `GitRepository` / `HelmRepository` API version | throughout `repos/` | `source.toolkit.fluxcd.io/v1beta2` |
| `HelmRelease` API version | throughout `repos/` | `helm.toolkit.fluxcd.io/v2beta1` |

**Crossplane**

| Component | Location | Pinned version |
|---|---|---|
| Crossplane Helm chart | `repos/gitops-system/tools/crossplane/crossplane-core/crossplane-release.yaml` | `1.15.0` |
| AWS provider package | `repos/gitops-system/tools/crossplane/crossplane-aws-provider/aws-provider.yaml` | `xpkg.upbound.io/crossplane-contrib/provider-aws:v0.47.1` |
| Kubernetes provider package | `repos/gitops-system/tools/crossplane/crossplane-k8s-provider/k8s-provider.yaml` | `xpkg.upbound.io/crossplane-contrib/provider-kubernetes:v0.13.0` |
| `ControllerConfig` API version | both provider manifests | `pkg.crossplane.io/v1alpha1` |
| AWS `ProviderConfig` API version | `.../crossplane-aws-provider-config/aws-providerconfig.yaml` | `aws.crossplane.io/v1beta1` |
| Managed resource API groups | `.../crossplane-eks-composition/composition.yaml`, `tools-config/*-iam/`, `gitops-workloads/` | `ec2.aws.crossplane.io/v1beta1`, `eks.aws.crossplane.io/v1beta1`, `eks.aws.crossplane.io/v1alpha1`, `iam.aws.crossplane.io/v1beta1`, `dynamodb.aws.crossplane.io/v1alpha1`, `kubernetes.crossplane.io/v1alpha1` |
| `Composition` mode | `.../crossplane-eks-composition/composition.yaml` | native resource mode (`spec.resources` with inline patches) |
| Workload cluster Kubernetes version | `repos/gitops-system/clusters-config/template/def/eks-cluster.yaml` | `eks-k8s-version: '1.28'`, `mng-k8s-version: '1.28'` |
| Node group AMI type | `.../crossplane-eks-composition/composition.yaml` | `AL2_x86_64` / `AL2_x86_64_GPU` |
| `kubectl` helper image | `.../crossplane-k8s-provider-config/k8s-providerconfig.yaml` | `bitnami/kubectl:1.22.11` |
| OIDC IdP thumbprint | `.../crossplane-eks-composition/composition.yaml` | hard-coded `9e99a48a9960b14926bb7f3b02e22da2b0ab7280` |

**Cluster add-ons**

| Component | Location | Pinned version |
|---|---|---|
| aws-load-balancer-controller chart | `repos/gitops-system/tools/aws-load-balancer-controller/aws-lb-controller-release.yaml` | `1.4.6` |
| aws-ebs-csi-driver chart | `repos/gitops-system/tools/aws-ebs-csi/aws-ebs-csi-release.yaml` | `2.30.0` |
| external-secrets chart | `repos/gitops-system/tools/external-secrets/external-secrets-release.yaml` | `0.4.4` |
| sealed-secrets chart | `repos/gitops-system/tools/sealed-secrets/sealed-secrets-release.yaml` | `2.7.1` |
| karpenter chart | `repos/gitops-system/tools/karpenter/karpenter-release.yaml` | `0.36.1` |
| kubecost cost-analyzer chart | `repos/gitops-system/tools/kubecost/kubecost-release.yaml` | `2.2.2` |
| kubecost-modeling image | same | `v0.1.6` |
| Karpenter `NodePool` API version | `repos/gitops-system/tools-config/karpenter-config/node-pool.yaml` | `karpenter.sh/v1beta1` |
| Karpenter `EC2NodeClass` API version | same | `karpenter.k8s.aws/v1beta1` |
| Karpenter node AMI family | same | `AL2` |
| Karpenter consolidation policy | same | `WhenUnderutilized` |
| Sealed Secrets version label | `repos/gitops-system/clusters-config/template/secrets/namespace.yaml` | `v0.26.3` |

**Sample applications**

| Component | Location | Pinned version |
|---|---|---|
| API base image | `repos/apps/product-catalog-api/{v1,v2}/Dockerfile` | `python:3.9-slim` |
| Frontend base image | `repos/apps/product-catalog-fe/Dockerfile` | `node:14` |
| API Python dependencies (v1) | `repos/apps/product-catalog-api/v1/requirements.txt` | `flask-restx==1.3.0`, `Flask==3.1.3`, `werkzeug==3.1.6`, `gunicorn==23.0.0`, `requests==v2.33.0`, `flask-cors==6.0.0`, `boto3==1.35.39`, `markupsafe==2.1.5` |
| API Python dependencies (v2) | `repos/apps/product-catalog-api/v2/requirements.txt` | as above, except `Flask==3.0.3`, `werkzeug==3.0.6` |
| Frontend npm dependencies | `repos/apps/product-catalog-fe/package.json` | `axios ^1.18.0`, `body-parser ^1.20.8`, `ejs ^3.1.10`, `express ^4.22.3`, `prom-client ^14.0.1`, `nodemon ^2.0.18` |
| Frontend deployment image tag | `repos/apps-manifests/product-catalog-fe-manifests/kubernetes/overlays/{prod,staging}/deployment.yaml` | `:latest` |

### Known breaking changes to be handled

Research against upstream sources identified the following migrations that the upgrade forces, rather than optional cleanups:

- **Flux beta API removal.** Flux v2.7 removed `source.toolkit.fluxcd.io/v1beta1`, `kustomize.toolkit.fluxcd.io/v1beta1`, `helm.toolkit.fluxcd.io/v2beta1`, `image.toolkit.fluxcd.io/v1beta1`, and `notification.toolkit.fluxcd.io/v1beta1`; Flux v2.8 removed `source.toolkit.fluxcd.io/v1beta2`, `kustomize.toolkit.fluxcd.io/v1beta2`, and `helm.toolkit.fluxcd.io/v2beta2` ([Flux upgrade procedure for v2.7+](https://github.com/fluxcd/flux2/discussions/5572)). Every `Kustomization`, `GitRepository`, `HelmRepository`, and `HelmRelease` in this repository uses an API version in those removed sets.
- **Crossplane v2 is deliberately out of scope.** Crossplane maintains the v1.20 line alongside its v2 lines: v1.20.12 was published roughly three weeks ago, in the same period as v2.2.5, v2.3.5, and v2.4.0. Crossplane v2 drops native patch-and-transform composition (`spec.mode: Resources`), the `ControllerConfig` type, external secret stores, composite resource connection details, and the default-registry flag ([Upgrade to Crossplane v2](https://docs.crossplane.io/master/guides/upgrade-to-crossplane-v2/)). This repository's workload cluster bootstrap depends on composite resource connection details: `repos/gitops-system/tools-config/crossplane-eks-composition/compositeresourcedefinition.yaml` declares `connectionSecretKeys` including `cluster-ca` and `apiserver-endpoint`, the accompanying `Composition` declares `connectionDetails`, and `repos/gitops-system/clusters-config/template/def/eks-cluster.yaml` sets `writeConnectionSecretToRef` to the `flux-system` secret from which Flux is bootstrapped into each workload cluster. The upgrade therefore targets the Crossplane v1.20 line, and the v2 migration is a separate piece of work. Content was rephrased for compliance with licensing restrictions.
- **Crossplane AWS provider status corrected.** `crossplane-contrib/provider-aws` is actively maintained: the project published v0.59.0 on 12 August 2026 and carries commits dated after that release. An earlier reading of this repository's upgrade path treated the monolith as superseded, on the basis of a 2023 project-status discussion ([project status discussion](https://github.com/crossplane-contrib/provider-aws/issues/1954)); that reading is stale and is corrected here. The upgrade stays on the monolith package, so the `*.aws.crossplane.io` managed resource API groups and the `aws.crossplane.io/v1beta1` `ProviderConfig` in this repository are retained rather than migrated, and no per-service provider family is introduced. `crossplane-contrib/provider-kubernetes` is likewise carried forward, at v1.3.1.
- **Karpenter v1.** Karpenter v1.0 graduated the `NodePool` and `EC2NodeClass` APIs out of beta and shipped a documented set of breaking changes ([Karpenter v1 migration](https://karpenter.sh/v1.0/upgrading/v1-migration/)).
- **Amazon EKS version support.** Kubernetes `1.36` is available on Amazon EKS and `1.29` is far outside standard support ([EKS standard support release notes](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions-standard.html)). Kubernetes `1.32` is the final version for which Amazon EKS publishes Amazon Linux 2 AMIs. Both Target_Kubernetes_Version and Workload_Kubernetes_Version are above `1.32`, so the `AL2_x86_64` node group AMI type and the Karpenter `AL2` AMI family cannot be carried forward for either version.
- **`aws-auth` ConfigMap is deprecated but retained.** Amazon EKS deprecated the `aws-auth` ConfigMap in favour of access entries, and has not removed it: the ConfigMap continues to be honoured while the cluster authentication mode includes `CONFIG_MAP`, that is `CONFIG_MAP` or `API_AND_CONFIG_MAP` ([auth ConfigMap docs](https://docs.aws.amazon.com/eks/latest/userguide/auth-configmap.html)). Two constraints bound that choice: once `API` is enabled on a cluster it cannot be turned off, and a cluster that was not created with `CONFIG_MAP` enabled cannot have it enabled afterwards. This repository grants console and Karpenter node access through `aws-auth` in both the bootstrap steps and `repos/gitops-system/clusters/template/aws-auth.yaml`, and that path is kept.
- **AWS Cloud9 closed to new customers.** AWS stopped accepting new Cloud9 customers on 25 July 2024; only accounts that already had access may keep using the service ([AWS Cloud9 CLI reference](https://docs.aws.amazon.com/cli/latest/reference/cloud9/), with migration guidance in [How to migrate from AWS Cloud9](https://aws.amazon.com/blogs/devops/how-to-migrate-from-aws-cloud9-to-aws-ide-toolkits-or-aws-cloudshell/)). This is a forced migration of the same kind as the Flux beta API removals, not a modernization preference: `initial-setup/auto/cfn.yaml` declares `AWS::Cloud9::EnvironmentEC2`, so stack creation fails in any AWS account that lacks pre-existing Cloud9 access, and the automated setup path is unusable for a new reader regardless of any version pin. The replacement is VS Code served in the browser from an Amazon EC2 instance, following the reference template at `initial-setup/auto/reference/code-editor.yaml`. The Cloud9 instance was not only an editor: it was the SSM Run Command execution host for the automated setup path in `initial-setup/auto/cfn.yaml`, which declares `AWS::Cloud9::EnvironmentEC2`, an instance profile and role, a volume-resize document, and the setup Command documents that a CodeBuild project runs against that instance. The SSM orchestration is therefore retargeted rather than removed, and the Cloud9 parameters, `cloud9:` IAM actions, `CLOUD9_` environment variables, tag-based instance lookup, role-attach step, and Cloud9 stack output are removed. Content was rephrased for compliance with licensing restrictions.
- **AWS CodeCommit remains generally available.** The same announcement of 25 July 2024 that closed AWS Cloud9 to new customers also closed AWS CodeCommit to new customers, but AWS subsequently reversed that decision for CodeCommit: the service returned to general availability on 24 November 2025 and new customer sign-ups reopened ([AWS CodeCommit returns to general availability](https://aws.amazon.com/blogs/devops/aws-codecommit-returns-to-general-availability)). Unlike the Cloud9 environment, the CodeCommit repository option is therefore retained and is not migrated by this feature: the CodeCommit setup documentation under `initial-setup/doc/repos` and the CodeCommit repositories and IAM user declared in `initial-setup/auto/cfn.yaml` are all carried forward unchanged. The GitHub repository option is likewise retained, so both Git repository backends remain supported. Some third-party pages, and at least one AWS pricing page, still carry the superseded closure wording, so the July 2024 closure announcement must not be read as the current status of CodeCommit. Content was rephrased for compliance with licensing restrictions.
- **Runtime end-of-life.** `python:3.9-slim` and `node:14` both reference language runtimes that no longer receive upstream security support.
- **Unresolvable pins.** `requests==v2.33.0` carries a `v` prefix that PyPI does not use and names a version that has not been published; `express ^4.22.3` and `body-parser ^1.20.8` name npm versions that have not been published. These pins fail installation today, independently of any upgrade.

### Scope boundary

This feature changes version pins, the manifests and configuration those pins break, the development environment platform that hosts the setup, and the documentation describing them. This feature does not add new components to the solution, does not change the hub/spoke architecture, and does not change the repository layout or the set of Git repositories the solution assumes.

The following migrations are explicitly out of scope for this feature and are recorded as deferred future work:

- Migrating the Crossplane_Platform to a Crossplane v2 line, because v2 removes composite resource connection details that the workload cluster Flux bootstrap depends on.
- Replacing `ControllerConfig` with `DeploymentRuntimeConfig` for provider runtime configuration.
- Converting the EKS cluster `Composition` from native resource mode to Pipeline mode with the patch-and-transform function.
- Replacing `aws-auth` ConfigMap access with EKS access entries.

## Glossary

- **GitOps_Solution**: The complete sample implementation contained in this repository, comprising `initial-setup`, `repos`, `bin`, `clean-up`, and the documentation files.
- **Pinned_Component**: A single third-party artifact whose version is stated in a repository file. Helm charts, container images, Crossplane packages, Kubernetes API versions, Kubernetes cluster versions, CLI tools, Python distributions, and npm packages are each Pinned_Components.
- **Version_Reference**: One occurrence in one file of a version string for a Pinned_Component, identified by file path and the field or line containing the version string.
- **Version_Scan**: The enumeration activity that locates Version_References across the GitOps_Solution.
- **Version_Inventory**: The recorded output of the Version_Scan, held in a file under the spec directory, listing every Version_Reference with the current version, the Target_Version, and the source of record consulted.
- **Target_Kubernetes_Version**: The highest Kubernetes minor version that Amazon EKS lists on standard support at the time the upgrade is performed.
- **Workload_Kubernetes_Version**: The Kubernetes minor version immediately preceding Target_Kubernetes_Version. The GitOps_Solution uses Workload_Kubernetes_Version for Workload_Cluster control planes and managed node groups by intent, so that the documented cluster upgrade scenario has a version gap to exercise.
- **Target_Version**: For a given Pinned_Component, the highest generally available release that is published in the component's upstream registry, is not a pre-release, and is documented by the component's maintainers as compatible with Target_Kubernetes_Version.
- **Bootstrap_Setup**: The assets used for the one-time initialization of the management cluster: `initial-setup/auto/cfn.yaml`, `initial-setup/config/mgmt-cluster-eksctl.yaml`, and the files under `initial-setup/config` and `initial-setup/secrets-template`.
- **Dev_Environment**: The browser-accessible VS Code development environment that the Bootstrap_Setup provisions, comprising an Amazon EC2 instance that serves VS Code together with the network and access resources that make it reachable. The Dev_Environment hosts the setup commands that the automated path runs, and replaces the AWS Cloud9 environment that the GitOps_Solution previously provisioned; because AWS Cloud9 is closed to new customers, the Dev_Environment is the only development environment the GitOps_Solution can provision for a new reader.
- **Flux_Manifests**: The Flux distribution manifests under `repos/gitops-system/clusters/mgmt/flux-system` and `repos/gitops-system/clusters/template/flux-system`, together with every `Kustomization`, `GitRepository`, `HelmRepository`, and `HelmRelease` resource in `repos`.
- **Crossplane_Platform**: The Crossplane Helm release, provider packages, provider runtime configuration, provider configuration, `CompositeResourceDefinition`, and `Composition` under `repos/gitops-system/tools/crossplane` and `repos/gitops-system/tools-config/crossplane-eks-composition`, together with every Crossplane managed resource manifest in `repos`.
- **Cluster_Addons**: The Helm releases and accompanying configuration for AWS Load Balancer Controller, AWS EBS CSI Driver, External Secrets Operator, Sealed Secrets, Karpenter, and Kubecost under `repos/gitops-system/tools` and `repos/gitops-system/tools-config`.
- **Cluster_Definition**: The workload cluster specification under `repos/gitops-system/clusters-config` that supplies the Kubernetes version and node group parameters consumed by the Crossplane_Platform.
- **Sample_Applications**: The application source, dependency manifests, container build files, and Kubernetes manifests under `repos/apps` and `repos/apps-manifests`.
- **Solution_Documentation**: `README.md`, `scenarios.md`, `initial-setup/README.md`, the files under `initial-setup/doc`, `repos/gitops-system/README.md`, `bin/README.md`, and `clean-up/README.md`.
- **Verification_Process**: The set of automated checks defined by this feature that confirm the upgraded GitOps_Solution resolves and reconciles.
- **Management_Cluster**: The EKS cluster created by the Bootstrap_Setup that hosts the hub Flux and Crossplane controllers.
- **Workload_Cluster**: An EKS cluster provisioned by the Management_Cluster through the Crossplane_Platform.
- **Duplicated_Reference**: A Version_Reference for a Pinned_Component that also appears, for the same purpose, in at least one other file within the GitOps_Solution.

## Requirements

### Requirement 1: Version inventory and discovery

**User Story:** As a platform engineer maintaining this sample, I want a complete inventory of every version pin and its current upstream state, so that the upgrade covers the whole solution and each version choice is traceable to a source.

#### Acceptance Criteria

1. THE Version_Scan SHALL enumerate Version_References in every text file of the GitOps_Solution across Helm chart versions, container image references, Crossplane package references, Kubernetes API versions, Kubernetes cluster versions, CLI tool versions in scripts and documentation, Python distribution pins, and npm package pins.
2. THE Version_Inventory SHALL contain exactly one entry for each Version_Reference that the Version_Scan enumerates, and no entry that does not correspond to a Version_Reference present in the GitOps_Solution.
3. THE Version_Inventory SHALL record, for each entry, a non-empty value for the file path, the field name or line number containing the version string, the current version string as it appears in that file, the Target_Version, the URL of the source of record consulted for the Target_Version, and the calendar date on which that source was consulted.
4. IF a Version_Reference names a version that is absent from the upstream registry of the corresponding Pinned_Component, THEN THE Version_Inventory SHALL mark that entry as unresolvable, retain the version string as it appears in the file, and record as the Target_Version the highest generally available non-pre-release version that the registry publishes for that Pinned_Component.
5. IF a Pinned_Component is superseded by a differently named upstream artifact, THEN THE Version_Inventory SHALL record the name of the successor artifact, the Target_Version of the successor artifact, and the URL of the maintainer statement that identifies the successor.
6. WHERE a Pinned_Component is a Duplicated_Reference, THE Version_Inventory SHALL list every file path at which the Version_Reference occurs together with the current version string recorded at each of those file paths.
7. WHERE a Pinned_Component is a Duplicated_Reference, THE Version_Inventory SHALL record one Target_Version that applies to every file path at which that Version_Reference occurs.
8. IF no maintainer-published page or upstream registry states a version for a Pinned_Component, THEN THE Version_Inventory SHALL mark that entry as lacking a source of record and SHALL record the current version string as the Target_Version.
9. IF a Version_Reference names a mutable tag rather than a version string that identifies a single immutable upstream artifact, THEN THE Version_Inventory SHALL mark that entry as mutable and SHALL record as the Target_Version a version string that identifies a single immutable upstream artifact.
10. WHERE a Version_Reference belongs to a Pinned_Component that this feature removes from the GitOps_Solution rather than upgrading, THE Version_Inventory SHALL mark that entry as removed and SHALL record the name of the component that replaces it.

### Requirement 2: Kubernetes and Amazon EKS version upgrade

**User Story:** As a platform engineer, I want the management cluster and the workload clusters to run a Kubernetes version that Amazon EKS supports, and the setup to run on a supported development environment, so that the sample deploys without incurring extended support charges or hitting unsupported version errors.

#### Acceptance Criteria

1. THE Bootstrap_Setup SHALL specify Target_Kubernetes_Version, as recorded in the Version_Inventory, as the Kubernetes version of the Management_Cluster in every Bootstrap_Setup file that states a Kubernetes cluster version.
2. THE GitOps_Solution SHALL use as Workload_Kubernetes_Version the Kubernetes minor version that is exactly one minor version below Target_Kubernetes_Version, and SHALL select Target_Kubernetes_Version and Workload_Kubernetes_Version such that Amazon EKS lists both on standard support in the source of record recorded in the Version_Inventory.
3. THE Cluster_Definition SHALL specify Workload_Kubernetes_Version as the Kubernetes version of the Workload_Cluster control plane.
4. THE Cluster_Definition SHALL specify Workload_Kubernetes_Version as the Kubernetes version of the Workload_Cluster managed node group, equal to the Kubernetes version it specifies for the Workload_Cluster control plane.
5. WHERE the Bootstrap_Setup exposes a Kubernetes version as a CloudFormation parameter, THE Bootstrap_Setup SHALL restrict the permitted values of that parameter to the Kubernetes minor versions that Amazon EKS lists on standard support in the source of record recorded in the Version_Inventory, include both Target_Kubernetes_Version and Workload_Kubernetes_Version among those permitted values, declare Target_Kubernetes_Version as the parameter default, and exclude every Kubernetes minor version that Amazon EKS lists on extended support or does not list.
6. WHERE the Bootstrap_Setup selects a `kubectl` download URL from a Kubernetes version, THE Bootstrap_Setup SHALL provide exactly one URL for each permitted value of the Kubernetes version parameter, each URL naming a released patch version of the same Kubernetes minor version as the permitted value that selects it.
7. WHERE a node group manifest specifies an AMI type, THE Crossplane_Platform SHALL specify an AMI type that Amazon EKS publishes for both Target_Kubernetes_Version and Workload_Kubernetes_Version, excluding any AMI type for which Amazon EKS ended AMI publication at a Kubernetes minor version lower than Workload_Kubernetes_Version.
8. WHERE a node configuration specifies an AMI family, THE Cluster_Addons SHALL specify an AMI family that Amazon EKS publishes for both Target_Kubernetes_Version and Workload_Kubernetes_Version, excluding any AMI family for which Amazon EKS ended AMI publication at a Kubernetes minor version lower than Workload_Kubernetes_Version.
9. WHERE a node group manifest specifies an AMI type for accelerated instances, THE Crossplane_Platform SHALL specify an accelerated-instance AMI type that Amazon EKS publishes for both Target_Kubernetes_Version and Workload_Kubernetes_Version.
10. THE Bootstrap_Setup SHALL specify an `eksctl` configuration API version that the Target_Version of `eksctl` accepts for creating a cluster at Target_Kubernetes_Version.
11. IF the Kubernetes version parameter of the Bootstrap_Setup is supplied a value that is not one of its permitted values, THEN THE Bootstrap_Setup SHALL stop before creating the Management_Cluster and report an error indicating that the supplied Kubernetes version is not permitted.
12. WHEN the Bootstrap_Setup installs `kubectl` for a permitted value of the Kubernetes version parameter, THE Bootstrap_Setup SHALL install a `kubectl` binary whose reported client minor version equals that permitted value.
13. THE Bootstrap_Setup SHALL provision the Dev_Environment as an Amazon EC2 instance that serves VS Code in the browser and that is reachable over HTTPS through an Amazon CloudFront distribution declared by the Bootstrap_Setup, following the resource pattern of the reference template at `initial-setup/auto/reference/code-editor.yaml`.
14. THE Bootstrap_Setup SHALL provision the Dev_Environment using only AWS services that accept new customers, such that the Bootstrap_Setup completes in an AWS account that has never had access to AWS Cloud9.
15. THE GitOps_Solution SHALL contain zero `AWS::Cloud9::*` resource declarations, zero IAM statements granting an action in the `cloud9` service namespace, zero CloudFormation parameters whose purpose is to configure a Cloud9 environment, zero environment variables whose names begin with `CLOUD9_`, zero documented steps that operate on a Cloud9 environment, and zero stack outputs that state a Cloud9 URL.
16. THE GitOps_Solution SHALL contain no file at `initial-setup/config/cloud9-role-permission-policy-template.json` and no Cloud9-specific screenshot asset under `initial-setup/img`, comprising `c9-modify-role.png`, `c9instancerole.png`, and `cloud9-role.png`.
17. THE Bootstrap_Setup SHALL name the Dev_Environment instance as the SSM Run Command execution target of every SSM Command document that the Bootstrap_Setup invokes, and SHALL retain every SSM Command document that the Bootstrap_Setup invoked before the Dev_Environment replaced the Cloud9 environment, except a document whose only purpose was to resize the environment volume.
18. THE Bootstrap_Setup SHALL grant the Dev_Environment its AWS permissions through an EC2 instance profile stated in the instance declaration that creates the Dev_Environment instance, such that the Bootstrap_Setup performs no post-creation instance-profile association, no instance reboot to pick up that association, and no managed-credentials disable operation.
19. THE Bootstrap_Setup SHALL state the size of the Dev_Environment root volume in the instance declaration that creates the Dev_Environment instance, such that the Bootstrap_Setup performs no post-creation volume resize operation.
20. THE Dev_Environment SHALL run an operating system version for which the operating system vendor publishes security updates on the date the upgrade is committed.
21. THE Bootstrap_Setup SHALL declare a stack output whose value is the URL at which the Dev_Environment is reachable.
22. THE Bootstrap_Setup SHALL permit inbound network access to the Dev_Environment instance only from the AWS-managed prefix list for CloudFront origin-facing address ranges in the Region in which the stack is created, and SHALL declare no inbound rule on the Dev_Environment security group whose source is outside that prefix list.
23. THE Bootstrap_Setup SHALL store the credential required to access the Dev_Environment in AWS Secrets Manager, and SHALL state zero literal Dev_Environment credential values in any template file.
24. IF the Dev_Environment does not become reachable at the URL stated in the stack output within 20 minutes of the Dev_Environment instance entering the running state, THEN THE Bootstrap_Setup SHALL report a failure identifying the Dev_Environment as the failing resource and SHALL stop before running the setup documents.

### Requirement 3: Flux upgrade and API migration

**User Story:** As a platform engineer, I want Flux and every Flux resource in the repository on current APIs, so that reconciliation succeeds instead of failing on API versions the installed controllers no longer serve.

#### Acceptance Criteria

1. THE Flux_Manifests SHALL reference the source-controller, kustomize-controller, helm-controller, and notification-controller container images at the image tags that the Flux project publishes as the controller releases belonging to the Target_Version of the Flux distribution.
2. THE Flux_Manifests SHALL declare each `Kustomization` resource using a `kustomize.toolkit.fluxcd.io` API version that the Target_Version of kustomize-controller serves and does not mark deprecated.
3. THE Flux_Manifests SHALL declare each `GitRepository` and `HelmRepository` resource using a `source.toolkit.fluxcd.io` API version that the Target_Version of source-controller serves and does not mark deprecated.
4. THE Flux_Manifests SHALL declare each `HelmRelease` resource using a `helm.toolkit.fluxcd.io` API version that the Target_Version of helm-controller serves and does not mark deprecated.
5. WHERE the Target_Version of a Flux controller removes or renames a field that a Flux resource in the Flux_Manifests sets, THE Flux_Manifests SHALL set the field that the Target_Version accepts for that behaviour, so that the set of objects applied by that resource and the order in which its dependencies are reconciled are unchanged from before the upgrade.
6. THE Bootstrap_Setup SHALL install a Flux CLI release whose major and minor version equal the major and minor version of the Flux distribution version declared in the Flux_Manifests.
7. THE Solution_Documentation SHALL state a Flux CLI installation command that installs a Flux CLI release whose major and minor version equal the major and minor version of the Flux distribution version declared in the Flux_Manifests.
8. THE Flux_Manifests SHALL declare the same Flux distribution version, the same controller image tags, and the same custom resource API versions in the management cluster directory and in the workload cluster template directory.
9. WHEN Flux reconciles the Management_Cluster after the upgrade, THE Management_Cluster SHALL report `Ready=True` for every `Kustomization` resource in the `flux-system` namespace within 600 seconds of that reconciliation starting.
10. THE Flux_Manifests SHALL state a served, non-deprecated API version in every field that names a Flux API group version outside a resource's own `apiVersion` field, including dependency references and health check references.
11. WHEN the Flux_Manifests are applied to the Management_Cluster, THE Management_Cluster SHALL serve every Flux API group version that the Flux_Manifests declare.
12. IF a `Kustomization` or `HelmRelease` resource in the `flux-system` namespace does not reach `Ready=True` within 600 seconds of its reconciliation starting, THEN THE Management_Cluster SHALL report a not-ready status condition on that resource identifying the reconciliation failure, and SHALL leave the objects previously applied by that resource in place.

### Requirement 4: Crossplane core and provider upgrade

**User Story:** As a platform engineer, I want Crossplane and its providers on maintained releases, so that workload cluster provisioning continues to work and receives upstream fixes.

#### Acceptance Criteria

1. THE Crossplane_Platform SHALL pin the Crossplane Helm chart to Target_Version expressed as a single exact chart version, containing no version range, wildcard, or floating reference.
2. THE Crossplane_Platform SHALL pin the Crossplane Helm chart to a chart version in the Crossplane `1.20` minor release line, being the highest patch release published in that line as recorded in the Version_Inventory.
3. THE Crossplane_Platform SHALL reference the `crossplane-contrib/provider-aws` package, pinned to Target_Version expressed as an exact immutable package tag or digest, and SHALL reference exactly one AWS provider package.
4. THE Crossplane_Platform SHALL reference the `crossplane-contrib/provider-kubernetes` package, pinned to Target_Version expressed as an exact immutable package tag or digest.
5. THE Crossplane_Platform SHALL declare every Crossplane managed resource using an API group and version that the referenced AWS provider package version or the referenced Kubernetes provider package version serves, and SHALL declare zero managed resource whose API group or version neither referenced provider package version serves.
6. THE Crossplane_Platform SHALL declare the AWS `ProviderConfig` using an API version that the referenced AWS provider package version serves.
7. THE Crossplane_Platform SHALL authenticate the AWS provider to the AWS API using IAM roles for service accounts, and SHALL contain zero long-lived AWS access key identifiers or secret access keys in any manifest or secret it declares.
8. THE Crossplane_Platform SHALL configure provider runtime settings using a resource kind and API version that the pinned Crossplane chart version serves.
9. WHERE the Crossplane_Platform configures provider runtime settings using `ControllerConfig`, THE Solution_Documentation SHALL state that `ControllerConfig` is deprecated upstream and SHALL record replacing it with `DeploymentRuntimeConfig` as deferred future work.
10. THE Crossplane_Platform SHALL define the EKS cluster `Composition` using a `Composition` mode that the pinned Crossplane chart version serves.
11. WHERE the EKS cluster `Composition` uses native resource mode, THE Solution_Documentation SHALL record converting that `Composition` to Pipeline mode with the patch-and-transform function as deferred future work.
12. THE Crossplane_Platform SHALL remain on a Crossplane version that serves composite resource connection details, and SHALL declare zero dependency on a Crossplane version that has removed composite resource connection details.
13. THE Crossplane_Platform SHALL publish the Workload_Cluster connection details through the EKS cluster composite resource and SHALL write them to the connection secret that the Cluster_Definition names, so that the Flux bootstrap of each Workload_Cluster reads its cluster credentials from that secret.
14. THE Crossplane_Platform SHALL publish exactly the three connection details of the EKS cluster `Composition` that the current manifests publish, comprising the cluster certificate authority, the API server endpoint, and the kubeconfig, using the same connection detail names as the current manifests.
15. THE Crossplane_Platform SHALL preserve the composed resource set of the EKS cluster `Composition`, comprising the VPC, the internet gateway, four subnets, two Elastic IP addresses, two NAT gateways, three route tables, the EKS cluster, the managed node group, the OIDC identity provider, and the cluster information and remote bootstrap objects, with no composed resource added to or removed from that set.
16. WHEN every composed resource of the EKS cluster `Composition` reports a ready status, THE Crossplane_Platform SHALL report the corresponding composite resource as ready, and until then SHALL report it as not ready.
17. WHEN the EKS cluster `Composition` provisions the OIDC identity provider, THE Crossplane_Platform SHALL set the thumbprint list to exactly one value: the documented well-known AWS OIDC root-CA thumbprint constant (Starfield Services Root CA G2, `9e99a48a9960b14926bb7f3b02e22da2b0ab7280`), accompanied by a comment recording that it is this well-known constant, that provider-aws v0.59.0 requires a 40-char SHA-1 thumbprint (the field cannot be omitted) while Crossplane patches cannot compute one, and that AWS validates EKS OIDC endpoints against its own trusted-CA store rather than the supplied value; and THE Crossplane_Platform SHALL NOT contain any per-cluster or hand-copied thumbprint value that could silently go stale.
18. THE Crossplane_Platform SHALL reference a `kubectl` helper container image pinned to an exact immutable image tag or digest, excluding floating tags such as `latest`, whose minor version is no more than one minor version below and no more than one minor version above Target_Kubernetes_Version.
19. WHEN the Crossplane_Platform reconciles a managed resource that already exists in AWS for an existing Workload_Cluster, THE Crossplane_Platform SHALL adopt that existing AWS resource without deleting, recreating, or replacing it.
20. THE Solution_Documentation SHALL state that migrating the Crossplane_Platform to Crossplane v2 is out of scope for this feature, SHALL name composite resource connection details, native patch-and-transform composition, and `ControllerConfig` among the capabilities that v2 removes, and SHALL link to the upstream Crossplane v2 upgrade guide using a URL that resolves to a reachable page.
21. IF an installed provider package does not report a healthy, installed status within 15 minutes of the referencing manifest being applied, THEN THE Crossplane_Platform SHALL report a failure status on that provider package identifying the reason for the failure, and SHALL leave the managed resources of every existing Workload_Cluster unchanged.
22. IF the EKS cluster `Composition` fails validation or fails to render composed resources, THEN THE Crossplane_Platform SHALL report a failure status on the affected composite resource identifying the reason for the failure, and SHALL retain every previously composed resource of that composite resource.

### Requirement 5: Cluster add-on upgrade

**User Story:** As a platform engineer, I want every add-on chart and its configuration on current releases, so that the add-ons install successfully on the upgraded clusters.

#### Acceptance Criteria

1. THE Cluster_Addons SHALL pin the Helm chart of each add-on it contains — AWS Load Balancer Controller, AWS EBS CSI Driver, External Secrets Operator, Sealed Secrets, Karpenter, and Kubecost — to the Target_Version of that chart as an exact version string containing no range operator and no wildcard.
2. THE Cluster_Addons SHALL reference each container image by a version-specific tag or a digest for which the registry hosting that image returns an image manifest.
3. WHERE the Target_Version of an add-on Helm chart renames a values field that the Cluster_Addons set, THE Cluster_Addons SHALL set the field name that the Target_Version of that chart accepts in place of the former name.
4. WHERE the Target_Version of an add-on Helm chart removes a values field that the Cluster_Addons set, THE Cluster_Addons SHALL express that configuration using a values field that the Target_Version of that chart accepts.
5. WHERE the maintainers of an add-on publish, for its Target_Version, an IAM policy containing actions that are absent from the accompanying IAM policy document in the Cluster_Addons, THE Cluster_Addons SHALL add those actions to the accompanying IAM policy document.
6. THE Cluster_Addons SHALL declare each Karpenter `NodePool` and `EC2NodeClass` resource, including the node class reference inside each `NodePool`, using the API group and version that the CRDs shipped with the Target_Version of the Karpenter chart list as the storage version.
7. WHERE the Target_Version of the Karpenter chart renames a `NodePool` or `EC2NodeClass` field, or renames an enumerated value of such a field, THE Cluster_Addons SHALL use the name that the Target_Version of that chart accepts.
8. WHERE the Target_Version of the Karpenter chart requires a `NodePool` or `EC2NodeClass` field that the current Cluster_Addons resources omit, THE Cluster_Addons SHALL set that field to a value that the Target_Version CRD schema accepts.
9. WHERE an add-on Helm chart at its Target_Version declares a default tag for an auxiliary container image that the Cluster_Addons override, THE Cluster_Addons SHALL reference that auxiliary image at the tag declared by the Target_Version of that chart.
10. IF an add-on at its Target_Version distributes its CRDs in an artifact separate from its application chart, THEN THE Cluster_Addons SHALL reference that CRD artifact at the same version as the pinned application chart.
11. THE Cluster_Addons SHALL state in the Sealed Secrets namespace label the same version string, including major, minor, and patch components, as the Sealed Secrets controller image tag that the Target_Version of the sealed-secrets chart deploys.
12. THE Solution_Documentation SHALL install a `kubeseal` version whose major and minor version components equal the major and minor version components of the Sealed Secrets controller that the Target_Version of the sealed-secrets chart deploys.

### Requirement 6: Cluster access configuration

**User Story:** As a platform engineer, I want cluster access to keep working through the `aws-auth` ConfigMap path this sample already uses, so that the upgrade does not couple a version refresh to an authentication migration.

#### Acceptance Criteria

1. THE Bootstrap_Setup SHALL grant the console IAM entity access to the Management_Cluster through an entry in the `aws-auth` ConfigMap of the Management_Cluster.
2. THE Bootstrap_Setup SHALL grant the Karpenter node IAM role access to the Management_Cluster through an entry in the `aws-auth` ConfigMap of the Management_Cluster that lists the groups `system:bootstrappers` and `system:nodes` for that role.
3. THE GitOps_Solution SHALL retain the `aws-auth` ConfigMap manifest at `repos/gitops-system/clusters/template/aws-auth.yaml`, and THE Solution_Documentation SHALL retain the bootstrap steps that add the console IAM entity and the Karpenter node IAM role to the `aws-auth` ConfigMap.
4. THE Crossplane_Platform SHALL grant the console IAM entity access to each Workload_Cluster through an entry in the `aws-auth` ConfigMap of that Workload_Cluster.
5. THE Crossplane_Platform SHALL grant the Karpenter node IAM role access to each Workload_Cluster through an entry in the `aws-auth` ConfigMap of that Workload_Cluster that lists the groups `system:bootstrappers` and `system:nodes` for that role.
6. THE Bootstrap_Setup SHALL create the Management_Cluster with an EKS cluster authentication mode of `CONFIG_MAP` or `API_AND_CONFIG_MAP`, stated in the request that creates the cluster.
7. THE Crossplane_Platform SHALL create each Workload_Cluster with an EKS cluster authentication mode of `CONFIG_MAP` or `API_AND_CONFIG_MAP`, stated in the managed resource that creates the cluster.
8. WHEN Karpenter launches a node in a Workload_Cluster whose `aws-auth` ConfigMap contains the entry for the Karpenter node IAM role, THE Workload_Cluster SHALL report that node as `Ready` within 10 minutes of the node instance entering the running state.
9. IF the `aws-auth` ConfigMap of a Workload_Cluster cannot be applied, THEN THE Crossplane_Platform SHALL report the corresponding managed resource as `Ready=False` with a condition message identifying the Workload_Cluster and the IAM principal whose mapping was not applied, and SHALL leave the mappings already present in that ConfigMap in place.
10. THE Solution_Documentation SHALL state that Amazon EKS deprecated the `aws-auth` ConfigMap, SHALL link to the Amazon EKS guidance on the `aws-auth` ConfigMap using a URL that resolves to a reachable page, SHALL record migrating to EKS access entries as deferred future work, and SHALL state that enabling the `API` authentication mode on a cluster cannot be reversed and that a cluster created without `CONFIG_MAP` enabled cannot have `CONFIG_MAP` enabled afterwards.

### Requirement 7: Sample application upgrade

**User Story:** As a developer using this sample, I want the demonstration applications built on supported runtimes with installable dependencies, so that the container images build and the applications start.

#### Acceptance Criteria

1. THE Sample_Applications SHALL specify, in each Python application build file, a Python base image tag that names an explicit Python major.minor version whose upstream end-of-security-support date, as published in the CPython release schedule, is later than the date the upgrade is committed, and SHALL NOT use a floating tag such as `latest` or a major-only tag.
2. THE Sample_Applications SHALL specify, in the frontend build file, a Node.js base image tag that names an explicit even-numbered Node.js major version listed as Active LTS or Maintenance LTS in the Node.js release schedule on the date the upgrade is committed, and SHALL NOT use a floating tag such as `latest`.
3. THE Sample_Applications SHALL pin each Python distribution to an exact version, using the `==` operator, that is published on PyPI and resolvable by the package installer for the selected Python base image version.
4. THE Sample_Applications SHALL pin each npm package in the frontend package manifest to a range whose lower bound is a version published on the npm registry and resolvable by the npm client bundled in the selected Node.js base image.
5. THE Sample_Applications SHALL express each Python version pin as digits and separators only, in the exact form published on PyPI for that distribution, with no leading `v` or other non-published prefix or suffix.
6. THE Sample_Applications SHALL pin every Python distribution that appears in both the version 1 and version 2 API dependency files to the identical version string in both files, such that a character-by-character comparison of the shared entries reports no difference.
7. THE Sample_Applications SHALL provide a frontend lockfile in which every resolved version satisfies the corresponding range in the frontend package manifest, and in which every dependency declared in the package manifest is present, such that a lockfile-validating install completes without a lockfile-out-of-sync error.
8. THE Sample_Applications SHALL install frontend production dependencies using a lockfile-based install command whose options are accepted by the npm version bundled in the selected Node.js base image, and SHALL NOT use an option that the bundled npm version reports as unknown, unsupported, or removed.
9. THE Sample_Applications SHALL reference each application container image in every prod and staging deployment manifest using a tag that identifies a single immutable image, and SHALL NOT use the tag `latest` or any other tag that is reassigned to new image content.
10. WHEN a container image is built from a Sample_Applications build file, THE Verification_Process SHALL report a build exit status code of 0 within 600 seconds.
11. WHEN a Sample_Applications container is started from a built image, THE Verification_Process SHALL report status code 200 from the `/ping` health path on the container's exposed port within 60 seconds of container start, using a per-request timeout of 10 seconds.
12. IF the package installer cannot resolve a pinned dependency version during a container image build, THEN THE Verification_Process SHALL report a non-zero build exit status and identify the package name and requested version that failed to resolve, and SHALL NOT publish or tag an image from that build.
13. IF no status code 200 response is received from the `/ping` health path within 60 seconds of container start, THEN THE Verification_Process SHALL report the verification as failed and identify the application and the observed response status or timeout.

### Requirement 8: End-to-end flow preservation

**User Story:** As a platform engineer following the documented setup, I want the bootstrap-to-workload-cluster flow to work after the upgrade, so that the sample remains usable end to end.

#### Acceptance Criteria

1. WHEN the Bootstrap_Setup completes against an AWS account, THE Management_Cluster SHALL report status `ACTIVE` within 30 minutes of the start of the Bootstrap_Setup, with all managed node group nodes in `Ready` state.
2. WHEN the Management_Cluster is bootstrapped with Flux, THE Management_Cluster SHALL report `Ready=True` for the Crossplane, External Secrets Operator, and Sealed Secrets reconciliations within 15 minutes of the Flux bootstrap completing.
3. WHEN a Sealed Secret containing Git credentials is applied to the Management_Cluster, THE Management_Cluster SHALL produce the corresponding `Secret` resource, containing the same key names as the source credentials, within 60 seconds.
4. WHEN a Workload_Cluster definition is committed to the `gitops-system` content, THE Management_Cluster SHALL report `Ready=True` and `Synced=True` for the corresponding EKS cluster composite resource within 45 minutes of the commit being reconciled.
5. WHEN a Workload_Cluster reaches status `ACTIVE`, THE Management_Cluster SHALL install Flux into that Workload_Cluster through Crossplane reconciliation within 15 minutes, such that all Flux controller deployments in the Workload_Cluster report `Available`.
6. WHEN Flux is installed into a Workload_Cluster, THE Workload_Cluster SHALL report `Ready=True` for the AWS Load Balancer Controller, AWS EBS CSI Driver, Karpenter, and Crossplane reconciliations within 20 minutes of the Flux controllers becoming `Available`.
7. WHEN an application is onboarded to a Workload_Cluster using the steps documented in the scenarios documentation, THE Workload_Cluster SHALL report every pod of that application as `Ready` within 10 minutes of the onboarding commit being reconciled.
8. WHEN the version 2 API application is deployed, THE Workload_Cluster SHALL report `Ready=True` and `Synced=True` for the DynamoDB table managed resource that the application declares within 10 minutes of the deployment being reconciled.
9. WHEN the control plane Kubernetes version in a Cluster_Definition is changed from Workload_Kubernetes_Version to Target_Kubernetes_Version, THE Management_Cluster SHALL upgrade the corresponding Workload_Cluster control plane so that the Workload_Cluster reports Target_Kubernetes_Version within 60 minutes of the change being reconciled.
10. WHEN the managed node group Kubernetes version in a Cluster_Definition is changed from Workload_Kubernetes_Version to Target_Kubernetes_Version, THE Management_Cluster SHALL upgrade the corresponding managed node group so that every node reports Target_Kubernetes_Version and `Ready` state within 60 minutes of the change being reconciled.
11. WHEN a Workload_Cluster definition is removed from the `gitops-system` content, THE Management_Cluster SHALL delete the corresponding Workload_Cluster and every AWS resource composed for it within 45 minutes of the removal being reconciled, leaving zero managed resources for that cluster in the Management_Cluster.
12. WHEN a script in the `bin` directory is executed to generate manifests, THE generated manifests SHALL declare only `apiVersion` values served by the Flux_Manifests and Crossplane_Platform versions installed after the upgrade, so that validating those manifests against the Management_Cluster API server returns no unrecognized `apiVersion`, unrecognized kind, or deprecated `apiVersion` warning.
13. IF a reconciliation or managed resource named in criteria 2 through 11 does not reach its stated ready state within the stated time bound, THEN THE Management_Cluster or Workload_Cluster hosting it SHALL report that resource as not ready with a status message identifying the failing resource and the failure cause, SHALL leave already-reconciled resources in place without deleting them, and SHALL continue retrying reconciliation until the source content changes.
14. IF a Cluster_Definition specifies a Kubernetes version that is not offered by Amazon EKS or that is more than one minor version above the current Workload_Cluster version, THEN THE Management_Cluster SHALL reject the change, SHALL leave the Workload_Cluster running its current version, and SHALL report the composite resource as not ready with a status message indicating the version is invalid.

### Requirement 9: Documentation alignment

**User Story:** As a reader following this repository, I want the documentation to state the versions and steps the repository actually uses, so that following the instructions produces a working system.

#### Acceptance Criteria

1. THE Solution_Documentation SHALL state, for each Pinned_Component it mentions, the version recorded as the Target_Version for that Pinned_Component in the Version_Inventory, and SHALL contain no occurrence of the pre-upgrade version of that Pinned_Component.
2. WHERE the Solution_Documentation contains a tool installation command carrying a version in the URL or in an environment variable, THE Solution_Documentation SHALL state the Target_Version of that tool at every occurrence of that command.
3. THE Solution_Documentation SHALL reference only file and directory paths that are present in the GitOps_Solution.
4. WHERE an upgrade changes a step that a reader performs, THE Solution_Documentation SHALL state that step in its post-upgrade form, including the command the reader runs and the inputs that command requires.
5. WHERE an upgrade removes a step that a reader performs, THE Solution_Documentation SHALL contain no instruction, command listing, or referenced path for that step, and SHALL number the remaining steps of that procedure consecutively.
6. THE Solution_Documentation SHALL record, for each Pinned_Component whose upgrade required a manifest or configuration change, the name of that Pinned_Component, the change that was made, and a URL of upstream migration guidance that resolves to a reachable page published by that component's maintainers.
7. THE Solution_Documentation SHALL state, in the cluster upgrade scenario, the starting Kubernetes version as Workload_Kubernetes_Version and the resulting Kubernetes version as Target_Kubernetes_Version, and SHALL state no other Kubernetes version number in that scenario.
8. THE Solution_Documentation SHALL state that the Workload_Cluster Kubernetes version is one minor version below the Management_Cluster Kubernetes version by intent, and SHALL state that the intent is to give the documented cluster upgrade scenario a version gap to exercise.
9. THE Solution_Documentation SHALL name the AWS provider package that the Crossplane_Platform references after the upgrade.
10. THE Solution_Documentation SHALL link to the authentication guidance of the AWS provider package that the Crossplane_Platform references after the upgrade using a URL that resolves to a reachable page.
11. THE Solution_Documentation SHALL state, in place of the Cloud9 workspace preparation section, the steps by which a reader opens and uses the Dev_Environment that the Bootstrap_Setup provisions, including how the reader obtains the Dev_Environment URL and access credential.
12. THE Solution_Documentation SHALL contain no step, screenshot, or referenced policy template whose only purpose was to create an IAM policy or role and attach it to the Cloud9 instance, and SHALL contain no reference to `initial-setup/config/cloud9-role-permission-policy-template.json`.
13. THE Solution_Documentation SHALL state that a reader following the manual setup path may run its commands either from the Dev_Environment or from a terminal on a machine the reader already has, and SHALL state the tools that terminal requires.
14. THE Solution_Documentation SHALL state, in `clean-up/README.md`, the step that deletes the Dev_Environment, and SHALL state no step that deletes a Cloud9 environment.
15. THE Solution_Documentation SHALL state the operating system name and version of the Dev_Environment that the Bootstrap_Setup provisions.
16. IF a documented step instructs the reader to apply a manifest at a path that is absent from the GitOps_Solution, THEN THE Solution_Documentation SHALL instruct the reader to apply the manifest at the path where the GitOps_Solution provides the equivalent resource, or SHALL omit that step where the GitOps_Solution provides no equivalent resource.
17. WHEN the Verification_Process checks the Solution_Documentation, THE Verification_Process SHALL report each version string that differs from the Target_Version recorded in the Version_Inventory for the same Pinned_Component and each referenced repository path that is absent from the GitOps_Solution.
18. THE Solution_Documentation SHALL state that the development environment changed because AWS closed Cloud9 to new customers, and SHALL link to that statement using a URL that resolves to a reachable page stating that Cloud9 is unavailable to new customers.

### Requirement 10: Verification and validation

**User Story:** As a platform engineer reviewing this upgrade, I want automated checks that prove every version reference resolves and every manifest is valid, so that I can trust the upgrade without deploying it by hand.

#### Acceptance Criteria

1. WHEN the Verification_Process runs, THE Verification_Process SHALL build every Kustomize overlay and base in the GitOps_Solution, and SHALL exit with status code 0 if every build and every other executed check completes without error.
2. WHEN the Verification_Process runs, THE Verification_Process SHALL validate every Kubernetes manifest in the GitOps_Solution against the schema of the API version that manifest declares, using for custom resources the CustomResourceDefinition supplied by the component that owns the resource, and SHALL list each manifest whose schema cannot be located as unvalidated together with its file path and declared API version.
3. WHEN the Verification_Process runs, THE Verification_Process SHALL confirm that each pinned Helm chart version is listed in the index retrieved at run time from the `HelmRepository` that the corresponding `HelmRelease` references, comparing the exact version string with no range or wildcard matching.
4. WHEN the Verification_Process runs, THE Verification_Process SHALL confirm that each Crossplane package reference, including its tag, resolves in the registry named in the reference without AWS credentials.
5. WHEN the Verification_Process runs, THE Verification_Process SHALL confirm that each container image reference, including its tag or digest, resolves in the public registry named in the reference without AWS credentials.
6. WHEN the Verification_Process runs, THE Verification_Process SHALL confirm that each Python distribution pin resolves on PyPI as an exact version match for the interpreter version declared by the component that pins it.
7. WHEN the Verification_Process runs, THE Verification_Process SHALL confirm that each npm package pin resolves on the npm registry as an exact version match.
8. WHEN the Verification_Process runs, THE Verification_Process SHALL confirm that Target_Kubernetes_Version and Workload_Kubernetes_Version both appear in the set of Kubernetes versions that Amazon EKS reports as being in standard support on the day the check runs, and SHALL classify this check as one that requires an AWS account.
9. WHEN the Verification_Process runs, THE Verification_Process SHALL report each occurrence in the GitOps_Solution of an `AWS::Cloud9::` resource type, an IAM action in the `cloud9` service namespace, an environment variable name beginning with `CLOUD9_`, or a file path naming a removed Cloud9 asset, and SHALL exit with a non-zero status code if it finds one or more such occurrences.
10. IF the Verification_Process finds a Version_Reference for which the consulted source returns a not-found result, THEN THE Verification_Process SHALL report the file path, the reference including its version string, and the registry, index, or repository consulted.
11. IF the Verification_Process finds a Version_Reference that does not resolve, THEN THE Verification_Process SHALL continue running the remaining checks and exit with a non-zero status code.
12. WHEN the Verification_Process runs, THE Verification_Process SHALL validate the CloudFormation template in the GitOps_Solution using a validation that requires no AWS account, and IF that validation reports one or more errors, THEN THE Verification_Process SHALL report each error with its location in the template and exit with a non-zero status code.
13. WHERE a Duplicated_Reference exists, THE Verification_Process SHALL compare the version stated by every occurrence of that Version_Reference, and if any occurrence states a version that differs from another, SHALL report each occurrence with its file path and stated version and exit with a non-zero status code.
14. THE Verification_Process SHALL complete every check that requires no AWS account within 600 seconds of wall-clock time from invocation, and SHALL report by name each such check that did not complete within that limit.
15. IF a Kustomize build fails or a manifest fails schema validation, THEN THE Verification_Process SHALL report the file path, the resource name and kind, and the reported error, and SHALL exit with a non-zero status code.
16. IF a registry, chart index, or package repository consulted for a Version_Reference cannot be reached after 3 attempts with a 30-second timeout per attempt, THEN THE Verification_Process SHALL report that reference as unverified, distinct in its report from references reported as unresolved, and SHALL exit with a non-zero status code.
17. WHERE AWS credentials are not available, THE Verification_Process SHALL execute every check that requires no AWS account, report each check that requires an AWS account as skipped with the reason, and treat those skipped checks as not affecting the exit status code.
