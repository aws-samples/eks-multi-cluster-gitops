# Upgrade notes

This file records the component-version upgrade of the `eks-multi-cluster-gitops`
sample: what changed, where the upstream migration guidance lives, how an
operator should stage the change on already-running infrastructure, and which
migrations were deliberately deferred.

Version numbers below are the targets recorded in the version inventory
(`.kiro/specs/component-version-upgrade/version-inventory.yaml`), consulted
2026-11-20.

> **Editing this repository vs. upgrading a running cluster.** The ordering
> rules in the *Live-upgrade ordering* section are for an operator rolling this
> upgrade onto infrastructure that is already running from an earlier revision.
> They do **not** constrain the order in which the files in this repository are
> edited: nothing reconciles the source tree while the work is in progress, so
> intermediate states are inert. What must be correct is the finished tree.

## Migration log

For each pinned component whose upgrade required a manifest or configuration
change, the change made and a resolvable upstream migration reference.

| Component | Change made | Upstream migration reference |
|---|---|---|
| Flux distribution | `v2.1.2` → `v2.9.5`. Every `Kustomization`, `GitRepository`, and `HelmRepository` moved off `*.toolkit.fluxcd.io/v1beta2` to `/v1`, and every `HelmRelease` off `helm.toolkit.fluxcd.io/v2beta1` to `/v2` — the beta APIs Flux v2.7/v2.8 removed. Both `gotk-components.yaml` twins regenerated from the pinned CLI (controllers: source `v1.9.5`, kustomize `v1.9.5`, helm `v1.6.4`, notification `v1.9.4`). Group-versions stated outside a resource's own `apiVersion` (patch targets, health-check references, inline patch bodies) moved too. | https://github.com/fluxcd/flux2/discussions/5572 |
| Crossplane core | Helm chart `1.15.0` → `1.20.12`, staying on the v1.20 line (see deferred work below). | https://charts.crossplane.io/stable |
| Crossplane `provider-aws` | `crossplane-contrib/provider-aws` `v0.47.1` → `v0.59.0`. The monolith is actively maintained, so the `*.aws.crossplane.io` managed-resource groups and the `aws.crossplane.io/v1beta1` `ProviderConfig` are retained, not migrated. The OIDC IdP thumbprint is kept as the documented well-known AWS root-CA constant `9e99a48a9960b14926bb7f3b02e22da2b0ab7280` (Starfield Services Root CA G2): a live end-to-end run showed that deriving it from the issuer URL yields an AWS-invalid value ("Member must have length equal to 40"), and provider-aws v0.59.0 requires a 40-char SHA-1 thumbprint that a Crossplane patch cannot compute. AWS validates EKS OIDC against its own trusted-CA store, so the constant is safe. | https://github.com/crossplane-contrib/provider-aws/releases/tag/v0.59.0 |
| Crossplane `provider-kubernetes` | `crossplane-contrib/provider-kubernetes` `v0.13.0` → `v1.3.1`. | https://github.com/crossplane-contrib/provider-kubernetes/releases/tag/v1.3.1 |
| Karpenter | Chart `0.36.1` → `1.14.1`. `NodePool` → `karpenter.sh/v1`, `EC2NodeClass` → `karpenter.k8s.aws/v1`, `NodePool.spec.template.spec.nodeClassRef` rewritten to the v1 `group`/`kind`/`name` form (the `apiVersion` key is removed), and `disruption.consolidationPolicy` `WhenUnderutilized` → `WhenEmptyOrUnderutilized`. | https://karpenter.sh/v1.0/upgrading/v1-migration/ |
| Node OS: AL2 → AL2023 | Composition node-group AMI types `AL2_x86_64` → `AL2023_x86_64_STANDARD` (non-gpu) and `AL2_x86_64_GPU` → `AL2023_x86_64_NVIDIA` (gpu); Karpenter `EC2NodeClass.spec.amiFamily` `AL2` → `AL2023` with the now-required `spec.amiSelectorTerms: [- alias: al2023@latest]`. `amiFamily: AL2023` selects the `nodeadm` bootstrap mode. Kubernetes `1.32` is the last version for which Amazon EKS publishes AL2 AMIs, and both cluster tiers are above it. | https://docs.aws.amazon.com/eks/latest/userguide/al2023.html |
| Kubernetes / Amazon EKS versions | Management cluster → `1.36` (Target_Kubernetes_Version), workload cluster → `1.35` (Workload_Kubernetes_Version). CloudFormation `KubernetesVersion` `AllowedValues` and the kubectl download `Mappings` rewritten to the current standard-support minors. | https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions-standard.html |
| aws-load-balancer-controller | Chart `1.4.6` → `3.5.0` (v2 → v3 controller major bump). `HelmRelease` values reconciled against the target chart's schema; removed/renamed keys re-expressed. Live-run correction: the v3 controller hard-fails at startup fetching the VPC id from IMDS (`failed to get VPC ID ... ec2imds GetMetadata ... context deadline exceeded`) because the Crossplane-provisioned workload node group runs with IMDS hop limit 1, so pods can't reach IMDS; v2 tolerated this. Fixed by giving the controller its region and VPC id explicitly via chart values `region: ${AWS_REGION}` and `vpcId: ${VPC_ID}`, substituted per-cluster by `postBuild` from the `cluster-info` ConfigMap — which gained a new `VPC_ID` key (from the composed VPC's `status.atProvider.vpcId`) alongside the existing `AWS_REGION`. No node/IMDS change. | https://kubernetes-sigs.github.io/aws-load-balancer-controller/ |
| external-secrets | Chart `0.4.4` → `2.10.0` (two major lines). `HelmRelease` values reconciled against the target chart's schema. The `SecretStore` and `ExternalSecret` in `sealed-secrets-key.yaml` move to `external-secrets.io/v1`. Live-run correction: ESO 2.10.0 serves `v1` only (v1beta1 ships with `served=false`), so an interim v1beta1 target was insufficient and produced `no matches for kind "ExternalSecret" in version "external-secrets.io/v1beta1"` on Flux dry-run. | https://external-secrets.io/latest/guides/migrating-v1beta1-to-v1/ |
| aws-ebs-csi-driver | Chart `2.30.0` → `2.66.0`. | https://github.com/kubernetes-sigs/aws-ebs-csi-driver/blob/master/CHANGELOG.md |
| sealed-secrets | Chart `2.7.1` → `2.20.0`; namespace version label set to the controller image version the chart deploys. | https://github.com/bitnami-labs/sealed-secrets/blob/main/RELEASE-NOTES.md |
| kubecost cost-analyzer | Chart `2.2.2` → `2.8.4`, with the matching `kubecost-modeling` image tag `v0.1.31` (the tag chart 2.8.4 declares). Live-run correction: the target was first set to `2.9.6`, but the whole `2.9.x` line turned out to be a "prepare to upgrade to 3.0" **transition release** that hard-requires federation/transition config (cluster_id in two places plus a global federated store) and is not a valid standalone fresh-install target. Re-pinned to `2.8.4`, the highest **stable non-transition** cost-analyzer in the OCI registry `oci://public.ecr.aws/kubecost`. `global.clusterId`/`global.clusterName` are still set to `${CLUSTER_NAME}` per-cluster via `postBuild` substitution from the `cluster-info` ConfigMap (a mandatory value vs 2.2.2 that the offline diff missed because kubecost publishes no `values.schema.json`; valid and harmless in 2.8.x). The 2.9-only second cluster_id place (`prometheus.server.global.external_labels.cluster_id`) is dropped, since 2.8.x does not require it. | https://github.com/kubecost/cost-analyzer-helm-chart/releases |

## Live-upgrade ordering

The following applies **only** when rolling this upgrade onto a cluster that is
already running an earlier revision of this sample. It is operator guidance, not
a source-editing constraint — in this repository the intermediate states are
inert.

1. **Move node groups and `EC2NodeClass` resources to AL2023 before raising a
   running cluster's Kubernetes version above `1.32`.** Above that boundary
   Amazon EKS publishes no Amazon Linux 2 AMI, so a managed node group still
   declaring `AL2_x86_64` (or an `EC2NodeClass` still on `amiFamily: AL2`)
   cannot be created or replaced. Land the AL2023 change first, then raise the
   version.

2. **Apply the `gotk-components.yaml` change and the consuming Flux custom
   resource changes together, in one reconciliation.** The regenerated
   components alone leave existing beta resources unserved (their CRDs are gone);
   the resource changes alone fail admission against the old CRDs. Only applying
   both in the same reconciliation keeps the cluster admitting the resource set
   throughout.

3. **Follow the upstream Karpenter v1 migration order rather than applying the
   v1 manifests directly**, and schedule the node replacement that
   `amiFamily: AL2023` triggers — switching the AMI family rolls the nodes.

4. **`authenticationMode` cannot gain `CONFIG_MAP` after creation.** A cluster
   was created with a mode that includes `CONFIG_MAP` (this sample uses
   `API_AND_CONFIG_MAP`) or it can never be brought onto the retained `aws-auth`
   path — it must be recreated. Likewise, once `API` is enabled it cannot be
   disabled. See the *aws-auth retained* note below.

These constraints are exercised end to end by task 14 (the AWS-account
integration run); they are not checked by the offline verification suite.

## Rationale notes

### Workload / management version gap is intentional

The workload cluster runs Kubernetes `1.35` while the management cluster runs
`1.36` — one minor version below, by intent. The gap exists so the documented
cluster upgrade scenario (`scenarios.md`) has a real `1.35` → `1.36` upgrade to
exercise. It is not drift and should not be "corrected" by aligning the two.

### Crossplane v2 is out of scope (deferred)

The upgrade stays on the Crossplane **v1.20** line. Crossplane v2 removes
capabilities this sample depends on:

- **Composite resource connection details.** The workload cluster Flux bootstrap
  reads `cluster-ca`, `apiserver-endpoint`, and the kubeconfig from the composite
  connection secret that `writeConnectionSecretToRef` names. v2 drops composite
  connection details, which would break cluster onboarding. This is the binding
  reason v2 is deferred.
- **Native patch-and-transform composition.** The EKS cluster `Composition` uses
  native resource mode (`spec.resources` with inline patches); v2 drops it in
  favour of the function pipeline.
- **`ControllerConfig`.** v2 removes the `ControllerConfig` type
  (`pkg.crossplane.io/v1alpha1`) used for provider runtime settings.

Migrating to v2 is deferred future work. Upstream guide:
https://docs.crossplane.io/master/guides/upgrade-to-crossplane-v2/

### Default `gp3` StorageClass added for PVC-backed add-ons

The live run surfaced that the EKS `1.35` workload cluster ships **no default
StorageClass** — the only one present is a non-default `gp2` still naming the
removed in-tree provisioner `kubernetes.io/aws-ebs`. Add-ons whose PVCs leave
`storageClassName` empty (kubecost `cost-analyzer` and its bundled
`prometheus-server`) then bind to nothing and stay `Pending`. A default `gp3`
StorageClass backed by the already-deployed EBS CSI driver was added at
`repos/gitops-system/tools/aws-ebs-csi/storageclass-gp3.yaml`
(`provisioner: ebs.csi.aws.amazonaws.com`, `type: gp3`,
`volumeBindingMode: WaitForFirstConsumer`, `allowVolumeExpansion: true`,
`reclaimPolicy: Delete`, annotated
`storageclass.kubernetes.io/is-default-class: "true"`) and listed in that
directory's `kustomization.yaml`. Reference:
https://docs.aws.amazon.com/eks/latest/userguide/create-storage-class.html

### Crossplane IAM policy gained DynamoDB read actions

The live run surfaced that the sample-app `Table` reached `ACTIVE` in AWS but
its Crossplane managed resource stayed `Synced=False` with
`AccessDeniedException: not authorized to perform:
dynamodb:DescribeContinuousBackups`. provider-aws `v0.59.0` reads the table back
during its observe / drift-detection pass and calls more than the
create/update set granted. The embedded IAM policy in
`repos/gitops-system/tools-config/crossplane-iam/crossplane-iam.yaml` (statement
Sid `Stmt1658117635374`) was extended with the three read actions that observer
makes — `dynamodb:DescribeContinuousBackups`, `dynamodb:DescribeTimeToLive`, and
`dynamodb:ListTagsOfResource` — added together so successive observe calls don't
fail one after another. This is an install-time behaviour the offline scan could
not see. Reference:
https://github.com/crossplane-contrib/provider-aws/releases/tag/v0.59.0

### `aws-auth` ConfigMap is deprecated but retained

Amazon EKS deprecated the `aws-auth` ConfigMap in favour of access entries but
still honours it while the cluster authentication mode includes `CONFIG_MAP`.
This sample keeps the `aws-auth` path (console IAM entity and Karpenter node
role mappings, and `repos/gitops-system/clusters/template/aws-auth.yaml`) and
creates both cluster tiers with `authenticationMode: API_AND_CONFIG_MAP` —
which keeps `aws-auth` honoured while leaving access entries available for the
deferred migration. Two irreversibility constraints bound this choice:

- Once `API` is enabled on a cluster, it **cannot** be disabled.
- A cluster created **without** `CONFIG_MAP` can **never** have `CONFIG_MAP`
  enabled afterwards — it would have to be recreated.

Migrating to EKS access entries is deferred future work. EKS guidance:
https://docs.aws.amazon.com/eks/latest/userguide/auth-configmap.html

### Development environment changed because AWS closed Cloud9 to new customers

The Cloud9 environment was replaced with a browser-served VS Code environment on
an Amazon EC2 instance (following `initial-setup/auto/reference/code-editor.yaml`).
This is a forced migration, not a preference: AWS stopped accepting new Cloud9
customers on 25 July 2024, so the CloudFormation Cloud9 EC2 environment resource
fails stack creation in any account without pre-existing Cloud9 access. Reference (states Cloud9 is
unavailable to new customers, with migration guidance):
https://aws.amazon.com/blogs/devops/how-to-migrate-from-aws-cloud9-to-aws-ide-toolkits-or-aws-cloudshell/

**CodeCommit is retained, unlike Cloud9.** The same 25 July 2024 announcement
also closed AWS CodeCommit to new customers, but AWS reversed that decision:
CodeCommit returned to general availability on 24 November 2025 and reopened new
sign-ups. The CodeCommit repository option (setup docs under
`initial-setup/doc/repos` and the CodeCommit repositories and IAM user in
`initial-setup/auto/cfn.yaml`) is therefore carried forward unchanged. Some
third-party and AWS pricing pages still carry the superseded closure wording;
the July 2024 announcement is not the current status of CodeCommit. Reference:
https://aws.amazon.com/blogs/devops/aws-codecommit-returns-to-general-availability

### Automated setup: six live-run defects fixed (inventory FINDING 28, 29, 30, 31 & 32)

Deploying `initial-setup/auto/cfn.yaml` end to end surfaced six defects the
offline Cloud9 → VS Code retarget missed. All are now fixed in the template.

- **Setup docs assumed a `~/environment` workspace that no longer exists.** The
  retained SSM setup documents run as `OS_USER=ec2-user` and `cd
  /home/$OS_USER/environment` (and `cd ~/environment` inside their heredoc
  scripts). Cloud9 used to auto-create `~/environment`; the VS Code
  Dev_Environment's `CodeEditorSSMDoc` creates only `${DevEnvironmentHomeFolder}`
  (`/workshop`) for the `participant` user, so `/home/ec2-user/environment`
  never existed. The result was `cd: /home/ec2-user/environment: No such file
  or directory`, then a `git clone` "could not create work tree dir ...
  Permission denied", cascading to the dependent documents. Fix: each of the
  five documents that use `~/environment` (`CloneWorkshopRepo`,
  `CreateRootSealedSecretsEncryptionKeysDoc`, `SetupCodeCommitSSHAccessDoc`,
  `CloneCodeCommitReposDoc`, `CreateIAMRoleForCrossplaneDoc`) now runs `mkdir -p
  /home/$OS_USER/environment && chown $OS_USER: /home/$OS_USER/environment`
  immediately after its OS_USER `case`/`esac` block and before the first `cd` —
  a self-contained, order-independent per-document step. This is the same
  Cloud9-workspace assumption already flagged for the OS guard (inventory
  FINDING 8), simply not carried into the new instance by task 10.3/10.4.

- **CodeBuild masked setup failures, so the stack reported CREATE_COMPLETE over
  a failed setup.** In the `BuildProject` BuildSpec `build` phase both callers
  captured setup status with command substitution:
  `EXIT_CODE=$(process_command_status ...)`. But `process_command_status` echoes
  progress to stdout and reports failure via `return`, so `$(...)` captured the
  progress *text*, not the numeric return code; the failure was lost,
  `CODEBUILD_BUILD_SUCCEEDING` stayed 1, and `post_build` signalled SUCCESS to
  the WaitCondition. Fix (both the Configure-Workshop-Environment and
  Bootstrap-Git-And-Management-Cluster call sites): call `process_command_status`
  directly, capture its return code with `EXIT_CODE=$?`, and `exit $EXIT_CODE`
  (not `return`) on non-zero — so the build command terminates non-zero,
  CodeBuild marks the build failed, `post_build` signals FAILURE, and the stack
  rolls back. `process_command_status`'s own logic is unchanged.

- **Region resolved empty because the docs used token-less IMDSv1.** The setup
  documents derive the Region from the instance identity document with `curl -s
  http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r
  .region`. The AL2023 Dev_Environment base image requires IMDSv2, so the
  token-less request returned empty and `AWS_REGION` resolved to `""`. Every
  Region-dependent step then failed: eksctl with "AWS Region must be set" /
  "invalid input region --name", and `aws secretsmanager create-secret` against
  the malformed endpoint `secretsmanager..amazonaws.com` (exit 255). The empty
  value was also written into `~/.bash_profile` by the first step and inherited
  by the later login-shell documents (sealed-secrets, CodeCommit). Fix: the two
  places that derive the Region (`InstallK8sClientToolsDoc` and
  `CreateEKSClusterDoc`) now fetch an IMDSv2 token (`PUT /latest/api/token`) and
  pass it as the `X-aws-ec2-metadata-token` header before reading the identity
  document; the token approach works whether or not IMDSv1 is enabled, and the
  downstream login-shell documents inherit the corrected value from
  `~/.bash_profile`. Like the workspace-dir defect, this is a Cloud9 → VS
  Code migration consequence — Cloud9 set the Region for you.

- **kubeseal CLI never installed because the sealed-secrets repo was renamed.**
  The `installK8sClientTools` step derived the kubeseal version by curling
  `github.com/bitnami-labs/sealed-secrets/releases/latest` and reading the
  version tag off the redirect `location:` header. The repository was renamed
  from the `bitnami-labs` org to `bitnami`, so the old URL now returns a
  repo-rename redirect whose `location:` ends in `/latest` rather than
  `/releases/tag/vX.Y.Z`. The version parsed as the literal `latest`, the
  download URL `kubeseal-latest-linux-amd64.tar.gz` 404'd, `tar -xz` failed
  ("gzip: stdin: not in gzip format"), and `kubeseal` was never installed — the
  step still reported success only because the commands are not under `set -e`.
  The manual path was unaffected (it pins `v0.40.0` and uses `wget`, which
  follows the rename redirect without parsing a version). Fix: drop the
  latest-parsing logic and pin `KUBESEAL_VERSION=0.40.0` downloaded from the
  current `bitnami/sealed-secrets` org, consistent with `initial-setup/README.md`
  and the upgrade's pinning approach. Stale `bitnami-labs` references in
  `NOTICE.md`, `initial-setup/README.md`, and `repos/gitops-system/README.md`
  were corrected to `bitnami` as well.

- **Cloned repo was invisible in the editor (setup ran as the wrong user in the
  wrong folder).** Even after `~/environment` was created, the setup docs run as
  `ec2-user` and clone into `/home/ec2-user/environment` (mode `0700`), while the
  browser VS Code editor is served as the `participant` user and opens
  `/workshop`. `participant` can't even traverse `/home/ec2-user`, so the repo,
  the cloned CodeCommit repos, and the sealed-secrets keys all landed where the
  editor user couldn't see or reach them, and `/workshop` (what the editor
  opened) was empty. Cloud9 never had this split — it was single-user (the editor
  *was* `ec2-user`, opening `~/environment`). `/workshop` is also a lone migration
  artifact: every lab guide (`scenarios.md`, `bin/README.md`,
  `initial-setup/README.md`, `initial-setup/doc/repos/*.md`) roots its steps at
  `~/environment`. Fix: restore the single-user, `~/environment`-rooted model as
  `participant`. `CodeEditorSSMDoc` writes `/etc/workshop.env` (via `!Sub`,
  honouring the `DevEnvironmentUser`/`DevEnvironmentHomeFolder` params); each of
  the seven setup docs sources it right after OS detection and sets `OS_USER` to
  the participant user (every `$OS_USER` path and `~/environment` heredoc then
  follows automatically); and `DevEnvironmentHomeFolder` now defaults to
  `/home/participant/environment` so the folder the editor creates/opens, the
  clone target, and `~/environment` are the same place — keeping all lab guides
  correct. Verified live: the repo clones to
  `/home/participant/environment/eks-multi-cluster-gitops` owned by `participant`.

- **Setup scripts assumed the login user already had `~/.ssh` and a writable
  `~/.bash_profile` (broke once setup ran as `participant`).** `ec2-user` gets a
  `~/.ssh` at launch; the freshly `adduser`-created `participant` does not, so
  `setup_codecommit_ssh.sh`'s `cd ~/.ssh` failed and the generated key landed in
  the wrong place, then `kubectl create secret --from-file ~/.ssh/gitops` failed.
  Separately, the earlier root-context steps had created
  `/home/participant/.bash_profile` as root via `>>`, so the participant-run
  scripts hit "Permission denied" appending their `SSH_PUB_KEY_ID`/`REPO_PREFIX`
  exports. `setupCodeCommitSSHAccess` failed and the stack rolled back. Fix: in
  the first setup step (root) pre-create `/home/$OS_USER/.ssh` (0700) and
  `touch`+`chown` `/home/$OS_USER/.bash_profile` to the participant before any
  root append, so `~/.ssh` exists and `.bash_profile` stays participant-writable;
  plus a defensive `mkdir -p ~/.ssh` in the codecommit script. Verified live on a
  clean redeploy — the full bootstrap succeeds and `git-creds-system.yaml` is
  produced.

## Deferred future work

Recorded here as deferred, not implemented anywhere in this upgrade:

1. **Crossplane v2 migration** — v2 removes the composite resource connection
   details the workload-cluster Flux bootstrap depends on. See the rationale
   note above.
2. **`ControllerConfig` → `DeploymentRuntimeConfig`** — `ControllerConfig`
   (`pkg.crossplane.io/v1alpha1`) is deprecated upstream but still served by the
   v1.20 line, so replacing it is independent of this version bump.
3. **Native-mode `Composition` → Pipeline mode with the patch-and-transform
   function** — a behavioural rewrite of the inline-patch composition, not a
   version change; native mode remains served by v1.20.
4. **`aws-auth` ConfigMap → EKS access entries** — `aws-auth` is deprecated but
   still honoured; see the rationale note above.

## `eks-console/` path resolution decision

The earlier `initial-setup/README.md` step instructed the reader to apply
`gitops-system/tools-config/eks-console/role.yaml` and
`gitops-system/tools-config/eks-console/role-binding.yaml`. **No such
`eks-console/` directory exists in the repository.** Read-only EKS console
access is already granted through the `aws-auth` configuration: the
`eks-console-dashboard-full-access` `ClusterRole` and its binding at
`gitops-system/tools-config/aws-auth/role.yaml` and
`gitops-system/tools-config/aws-auth/role-binding.yaml` are applied by GitOps
once the management cluster is bootstrapped. The broken step was therefore
removed (per Requirement 9 criterion 16 — omit a step that references a path
the repository does not provide, where the equivalent resource is already
provided elsewhere); the reader only maps the console IAM entity into
`aws-auth`.
