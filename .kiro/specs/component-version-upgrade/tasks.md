# Implementation Plan: Component Version Upgrade

## Overview

This plan executes the 12 steps of the design's Execution Order and Dependencies section. Tasks 1–6, 8–12 and 14 correspond to steps 1–12; tasks 7 and 13 are checkpoints.

**Intermediate trees are inert.** This is a source-code change to a sample repository that nothing is currently deploying from. No cluster watches these files while the work is in progress, no controller admits or rejects them, and no AWS resource is created from them until someone deliberately runs the end-to-end flow. What must be correct is the *finished* tree, not every commit along the way. That distinction decides which constraints legitimately order the work, and the design's four categories apply here directly:

1. **Final-state consistency invariants** do not constrain edit order. They are properties of the finished tree — no Kubernetes version above 1.32 paired with an AL2 AMI type or AMI family (Property 11); every Flux, Crossplane and Karpenter group-version served by its pinned artifact (Properties 1, 2, 4, 5); the `gotk-components.yaml` twins in agreement (Property 3); every `duplicate_group` stating one target (Property 8). The verification suite decides each by enumeration, so a tree that violates one fails a check regardless of how it was assembled.
2. **Data dependencies** do constrain order, and they are the only thing that does. Task 1 gates every edit because it produces the target values those edits write. Task 12 genuinely goes last because it restates the final versions. The remaining producer/consumer pairs are task 4.2 → 4.4 (the thumbprint derivation decision), task 9.1 → 9.2 (the access-config field confirmation), and task 1.3 → tasks 5.1 and 8.4 specifically (the AL2023 accelerated AMI type name and the exact kubecost patch).
3. **Same-file write serialization** matters only when tasks run in parallel. It is a merge-conflict concern, not a correctness one, and imposes nothing under sequential execution.
4. **Live-cluster deployment ordering** is operator guidance for a reader who already has infrastructure running from an earlier revision of this sample. It does not constrain source editing. It is recorded in the migration notes (task 12.5) and exercised in the end-to-end run (task 14).

Tasks 5 and 6 are therefore unordered relative to each other, and areas B through H have no mutual data dependency.

Tasks 1–12 are validatable offline. Task 14 requires an AWS account and is a manual/integration run, not an offline coding task.

Out of scope, per the design's non-goals: Crossplane v2 migration, `ControllerConfig` → `DeploymentRuntimeConfig`, native → Pipeline-mode `Composition`, and `aws-auth` → EKS access entries. These are recorded as deferred future work in task 12.5, not implemented.

## Tasks

- [x] 1. Produce the Version Inventory
  - [x] 1.1 Create the inventory file and schema
    - Create `.kiro/specs/component-version-upgrade/version-inventory.yaml` with the `entries` mapping and the field set from the design Data Models section: `component`, `category`, `file`, `locator`, `current`, `target`, `status`, `successor`, `source_url`, `consulted`, `duplicate_group`, `notes`
    - Enforce one entry per Version_Reference occurrence — one file path per entry, never a list of paths
    - _Requirements: 1.2, 1.3_

  - [x] 1.2 Enumerate and record every Version_Reference
    - Scan every text file for the nine categories: `k8s-version`, `helm-chart`, `container-image`, `crossplane-package`, `k8s-api-version`, `cli-tool`, `python-dist`, `npm-package`, `aws-resource`
    - Record entries for the surfaces named in the design: `initial-setup/auto/cfn.yaml`, `initial-setup/config/mgmt-cluster-eksctl.yaml`, `initial-setup/README.md`, both `repos/gitops-system/clusters/{mgmt,template}/flux-system/gotk-components.yaml`, every Flux CR under `repos/`, `repos/gitops-system/tools/crossplane/**`, `repos/gitops-system/tools-config/crossplane-*/**`, `repos/gitops-system/tools/{aws-ebs-csi,aws-load-balancer-controller,external-secrets,karpenter,kubecost,sealed-secrets}/**`, `repos/gitops-system/tools-config/karpenter-config/node-pool.yaml`, `repos/gitops-system/clusters-config/template/**`, `repos/apps/**`, `repos/apps-manifests/**`, and the Solution_Documentation file set
    - Populate `target`, `source_url`, and `consulted` for each entry from the target versions fixed in the design
    - _Requirements: 1.1, 1.2, 1.3_

  - [x] 1.3 Resolve the two deferred pins and audit status flags and duplicate groups
    - Resolve the exact kubecost cost-analyzer patch within the `2.9.x` line (the current `2.x` major line; the target registry `oci://public.ecr.aws/kubecost` publishes up to `2.9.6`) and record it as an exact version string — a wildcard is not a permitted target
    - Resolve the AL2023 accelerated AMI type name that Amazon EKS publishes for both `1.36` and `1.35`, for the `workload-type: gpu` branch of the composition map transform, and record it with its source URL and consulted date
    - Assign exactly one status flag per entry: `upgrade`, `unresolvable` (`requests==v2.33.0`, `express ^4.22.3`, `body-parser ^1.20.8`), `superseded`, `no-source`, `mutable` (frontend `:latest` tags), or `removed` (Cloud9 parameters and assets, OIDC thumbprint literal) with a `successor`
    - Assign `duplicate_group` values to every Duplicated_Reference, including the two `gotk-components.yaml` twins, the Flux CLI pair in `cfn.yaml` and `initial-setup/README.md`, the Sealed Secrets version triple, and the frontend image tag pair; assert one identical `target` per group
    - _Requirements: 1.4, 1.5, 1.6, 1.7, 1.8, 1.9, 1.10, 5.1_
    - _Properties: Property 8, Property 12_

- [x] 2. Build the verification suite skeleton
  - [x] 2.1 Create the suite harness
    - Create `verify/run.sh` as the single entry point that runs each check as an independent module, aggregates results, and returns one exit code
    - Exit `0` only when every executed check completes without error; non-zero on any resolution, build, schema, lint, duplicate-divergence, or residue failure
    - A failing module must not prevent the remaining modules from running; report file path, resource, and observed error per failure
    - Report unreachable registries as *unverified*, distinct from *unresolved*, after 3 attempts at a 30-second timeout each
    - Enforce a 600-second wall-clock budget over the credential-free checks and report by name any check that exceeds it
    - _Requirements: 10.1, 10.10, 10.11, 10.14, 10.15, 10.16_

  - [x] 2.2 Implement checks 1 and 2 — Kustomize build and schema validation
    - Check 1: `kustomize build` over every `kustomization.yaml` under `repos/`
    - Check 2: `kubeconform` with `--schema-location` covering built-in Kubernetes schemas plus a locally cached CRD schema set
    - Populate the CRD cache from the pinned artifacts themselves: Flux CRDs from the pinned `gotk-components.yaml`, Karpenter CRDs rendered from the pinned chart, Crossplane CRDs extracted from the pinned provider package images, and `EKSCluster` from the repository's own `compositeresourcedefinition.yaml`
    - List any manifest whose schema cannot be located as *unvalidated* with its path and declared API version rather than passing it
    - _Requirements: 10.1, 10.2, 10.15_
    - _Properties: Property 1, Property 2, Property 4, Property 5, Property 7_

  - [x] 2.3 Implement checks 3–7 — registry resolution
    - Check 3: each pinned chart version present as an exact string in the live index of the `HelmRepository` its `HelmRelease` references
    - Check 4: each Crossplane package reference including tag resolves via `crane manifest`
    - Check 5: each container image reference including tag or digest resolves via `crane manifest`
    - Check 6: each Python pin resolves on the PyPI JSON API as an exact version
    - Check 7: each npm pin resolves on the npm registry as an exact version
    - Run these five concurrently since they are network-bound and independent; reject any range or wildcard
    - _Requirements: 10.3, 10.4, 10.5, 10.6, 10.7_
    - _Properties: Property 12, Property 13_

  - [x] 2.4 Implement checks 8 and 12 — CloudFormation validity
    - Check 8: `cfn-lint` over `initial-setup/auto/cfn.yaml`, reporting each error with its template location
    - Check 12: parse the template and assert the `KubernetesVersion` `AllowedValues` list and the kubectl `Mappings` key set are equal
    - _Requirements: 2.6, 10.12_
    - _Properties: Property 9_

  - [x] 2.5 Implement checks 9, 10 and 11 — consistency, residue, and doc drift
    - Check 9: inventory-driven duplicate-group comparison — every entry sharing a `duplicate_group` states the same `target`, and the value at each stated file path matches it
    - Check 10: `ripgrep` scan for `AWS::Cloud9::` resource types, `cloud9` IAM actions, `CLOUD9_`-prefixed variables, and the removed Cloud9 asset paths
    - Check 11: every version string in the Solution_Documentation file set equals its inventory `target`, and every repository path the documentation references exists
    - _Requirements: 9.3, 9.17, 10.9, 10.13_
    - _Properties: Property 3, Property 8, Property 15, Property 16_

  - [x] 2.6 Implement check 13 — application build and smoke
    - Build each Sample_Applications image with a 600-second per-build allowance and assert exit status 0
    - Start each container and assert status 200 from `/ping` within 60 seconds using a 10-second per-request timeout
    - On unresolved dependency, report the package name and requested version and publish no image
    - _Requirements: 7.10, 7.11, 7.12, 7.13_

  - [x] 2.7 Implement checks 14 and 15 — AWS-gated modules
    - Check 14: `aws eks describe-cluster-versions` confirming Target_Kubernetes_Version and Workload_Kubernetes_Version are both in standard support on the day the check runs
    - Check 15: harness for the end-to-end bootstrap and onboarding timing assertions
    - With no credentials present, report both as skipped with a reason and do not influence the exit code
    - _Requirements: 10.8, 10.17_
    - _Properties: Property 10, Property 11_

- [x] 3. Flux upgrade and API cutover
  - [x] 3.1 Apply the entire Flux cutover as a single change
    - **One logical change across four edit surfaces, kept together for reviewability.** The four are: the two generated files in each `flux-system` directory — `gotk-components.yaml` (surface 1, replaced wholesale by regenerated output) and `gotk-sync.yaml` (surface 2, edited in place or regenerated with its placeholder and path re-inserted) — the Flux custom resources under `repos/` (surface 3), and the group-versions stated outside a resource's own `apiVersion` (surface 4). `bin/*.sh` is **not** among them; see the note below. Editing `gotk-components.yaml` before or after the resources that consume it is equally safe, because nothing reconciles the tree while the work is in progress. The reason to keep the surfaces in one task is that splitting them invites landing half the change and leaving the finished tree inconsistent. The finished-tree consistency requirement is Correctness Properties 1–3, enforced by verification check 2 — whose CRD cache is extracted from the same `gotk-components.yaml` being validated against, so a surviving removed group-version has no schema. The separate requirement that an operator apply the component and resource changes together in one reconciliation is live-cluster guidance, recorded in task 12.5.
    - Surface 1 — regenerate both `gotk-components.yaml` twins with the Flux CLI; do **not** value-edit them. The file embeds six CRDs with full OpenAPI schemas, so a `v1beta2` schema cannot be string-edited into the target's `v1` schema set, and check 2's CRD cache is extracted from this same file — a hand-edited file would validate the repository's custom resources against schemas that do not match the running controllers. The procedure is generate-and-diff:
      - Install the Flux CLI pinned at the **current** version (`v2.1.2`), run `flux install --export`, and diff the output against the checked-in `repos/gitops-system/clusters/mgmt/flux-system/gotk-components.yaml`. An empty diff establishes the file is unmodified stock output and regeneration is safe. A non-empty diff **is** the local customization and must be re-applied on top of the new output — skipping this step is how a local modification gets silently dropped.
      - Install the Flux CLI pinned at the target distribution version, run `flux install --export`, write the output once, and copy that single file to both `repos/gitops-system/clusters/mgmt/flux-system/gotk-components.yaml` and `repos/gitops-system/clusters/template/flux-system/gotk-components.yaml`. This satisfies Correctness Property 3 by construction rather than by performing the same edit twice.
      - `flux install --export` is offline and needs no cluster and no credentials. `flux bootstrap` MUST NOT be used — it writes to a cluster and to a git repository.
      - The emitted controller versions are authoritative. If they differ from the design's listed values (source-controller `v1.9.5`, kustomize-controller `v1.9.5`, helm-controller `v1.6.4`, notification-controller `v1.9.4`), correct the design table and the matching Version Inventory entries to the emitted output — do not edit the generated file to match the inventory. Otherwise documentation-drift check 11 fails against a file that is correct by construction.
    - Surface 2 — `gotk-sync.yaml` in both `flux-system` directories: a `GitRepository` on `source.toolkit.fluxcd.io/v1beta2` and a `Kustomization` on `kustomize.toolkit.fluxcd.io/v1beta2`, both cut over to `/v1`. Regenerated output cannot simply be dropped over these files: each holds the `REPO_PREFIX/gitops-system` placeholder in `spec.url` and a per-cluster `spec.path` (`./clusters/mgmt` in the mgmt twin, `./clusters/cluster-name` in the template twin), both substituted by the `bin` scripts. Either edit the two `apiVersion` lines in place, or regenerate and re-insert the placeholder and the path. The two files legitimately differ, so no twin-equality assertion applies to them. The `cluster-name` and `REPO_PREFIX` placeholders must survive the edit — that is what Requirement 8 criterion 12 constrains, and it is discharged here by preserving the placeholders in this template rather than by any change to the `bin` scripts.
    - Surface 3 — every Flux CR under `repos/`: `Kustomization` → `kustomize.toolkit.fluxcd.io/v1`, `GitRepository` and `HelmRepository` → `source.toolkit.fluxcd.io/v1`, `HelmRelease` → `helm.toolkit.fluxcd.io/v2`
    - Surface 4 — group-versions stated outside a resource's own `apiVersion`. The real sites in this repository are: the kustomize `spec.patches[].target` `group` + `version` key pair (22 occurrences repo-wide; the Flux ones are in `clusters/mgmt/crossplane.yaml` and `clusters/template/crossplane.yaml`), `spec.healthChecks[].apiVersion` (naming `helm.toolkit.fluxcd.io/v2beta1` in `clusters-config/template/external-secrets.yaml`, `clusters-config/template/sealed-secrets.yaml`, and `tools/crossplane/crossplane-core.yaml`), and inline strategic-merge patch bodies carrying a group-version inside a YAML string. `spec.dependsOn` and both `sourceRef` forms are **not** such sites here — `dependsOn` carries only `- name:`, and `sourceRef`/`spec.chart.spec.sourceRef` carry only `kind`/`name`/`namespace` (inventory FINDING 7). All three real sites are missed by a grep on `apiVersion:` alone and must be searched for separately.
    - Note, so it is not re-added as a surface: the `bin/*.sh` generators were checked and carry zero Flux group-versions — they copy template directories and `sed` placeholder names or drive `yq` with field paths, and their one manifest-emitting heredoc at `bin/add-app-cluster-overlay.sh` line 15 emits `kustomize.config.k8s.io/v1beta1` (inventory FINDING 5).
    - Set `FLUX_VERSION` in `initial-setup/auto/cfn.yaml` to a `2.9` release, and use that same release as the CLI version that generates the surface 1 output, so following the documented install reproduces the checked-in manifests. `initial-setup/README.md` line 145 installs Flux unpinned (`curl -s https://fluxcd.io/install.sh | sudo bash`) and must be pinned to the same release — task 12.1 owns that README edit, so make it there rather than duplicating it here
    - Where the target controller renamed or removed a field a resource sets, set the replacement field so the applied object set, the `dependsOn` graph, and the prune and health-check semantics are unchanged
    - Completeness test before committing: a group-version-aware `ripgrep` for every removed group-version across the whole repository returns zero hits
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.8, 3.10, 3.11, 8.12_
    - _Properties: Property 1, Property 2, Property 3_

  - [x] 3.2 Run verification checks 1, 2 and 9
    - Schema validation uses the CRDs embedded in the same `gotk-components.yaml` being validated against, so a surviving removed group-version has no schema and fails
    - _Requirements: 10.1, 10.2, 10.13_

- [x] 4. Crossplane platform upgrade
  - [x] 4.1 Confirm the three `v1alpha1` managed resource group-versions are served
    - Read the CRDs shipped in `crossplane-contrib/provider-aws:v0.59.0` and `crossplane-contrib/provider-kubernetes:v1.3.1` and confirm each of `eks.aws.crossplane.io/v1alpha1` (`NodeGroup`), `kubernetes.crossplane.io/v1alpha1` (`Object`, `ProviderConfig`), and `dynamodb.aws.crossplane.io/v1alpha1` (sample app table) is served
    - Record the confirmation per group-version in the inventory with the package version consulted; zero managed resources may remain on an unserved group-version
    - _Requirements: 4.5, 4.6_
    - _Properties: Property 4_

  - [x] 4.2 Decide the OIDC thumbprint derivation and record it
    - Determine from the `OpenIDConnectProvider` CRD in the target package which of the two derivations applies: omit `thumbprintList` if `v0.59.0` populates it from the URL, otherwise patch it from the cluster's OIDC issuer through the existing `patches` mechanism, mirroring how `spec.forProvider.url` is already patched with a `TrimPrefix` transform
    - Record the chosen derivation and its basis in the inventory; the binding constraint is only that no literal thumbprint survives
    - _Requirements: 4.17_
    - _Properties: Property 17_

  - [x] 4.3 Apply the Crossplane version bumps
    - `repos/gitops-system/tools/crossplane/crossplane-core/crossplane-release.yaml`: chart `1.20.12` as a single exact version, no range or wildcard
    - `repos/gitops-system/tools/crossplane/crossplane-aws-provider/aws-provider.yaml`: `crossplane-contrib/provider-aws:v0.59.0`, exactly one AWS provider package
    - `repos/gitops-system/tools/crossplane/crossplane-k8s-provider/k8s-provider.yaml`: `crossplane-contrib/provider-kubernetes:v1.3.1`
    - `repos/gitops-system/tools-config/crossplane-k8s-provider-config/k8s-providerconfig.yaml`: replace `bitnami/kubectl:1.22.11` with an immutable tag within one minor of `1.36`
    - Leave `ControllerConfig`, the AWS `ProviderConfig`, the managed resource group-versions, and the native `Composition` mode unchanged
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.7, 4.8, 4.10, 4.12, 4.18_
    - _Properties: Property 12, Property 13_

  - [x] 4.4 Implement the thumbprint derivation and verify the connection-details chain
    - In `repos/gitops-system/tools-config/crossplane-eks-composition/composition.yaml`, replace the literal `9e99a48a9960b14926bb7f3b02e22da2b0ab7280` at `spec.resources[cluster-oidc-idp].base.spec.forProvider.thumbprintList[0]` per the decision recorded in 4.2
    - Structurally confirm the chain is unchanged: `compositeresourcedefinition.yaml` `connectionSecretKeys` `[cluster-ca, apiserver-endpoint, kubeconfig]` → composition `connectionDetails` publishing exactly three details named `cluster-ca`, `apiserver-endpoint`, `value` → `clusters-config/template/def/eks-cluster.yaml` `writeConnectionSecretToRef`
    - Confirm the composed resource set is preserved exactly — VPC, internet gateway, four subnets, two Elastic IPs, two NAT gateways, three route tables, EKS `Cluster`, managed `NodeGroup`, `OpenIDConnectProvider`, cluster-info and remote-bootstrap objects — with nothing added or removed
    - Before the provider bump lands, confirm external-name annotations on existing managed resources are preserved by `v0.59.0` so reconciliation adopts rather than replaces live infrastructure
    - _Requirements: 4.13, 4.14, 4.15, 4.16, 4.17, 4.19_
    - _Properties: Property 17, Property 18_

  - [x] 4.5 Run verification checks 2, 4 and 5, plus the secret-material scan
    - `ripgrep` for the removed thumbprint literal and for AWS long-lived key material patterns across `repos/` and `initial-setup/`
    - _Requirements: 4.7, 10.2, 10.4, 10.5_

- [x] 5. Node OS migration: AL2 → AL2023
  - [x] 5.1 Change both node group AMI types in the composition
    - In `repos/gitops-system/tools-config/crossplane-eks-composition/composition.yaml`, in the `map` transform on `spec.parameters.workload-type`: `non-gpu` branch `AL2_x86_64` → `AL2023_x86_64_STANDARD`, `gpu` branch `AL2_x86_64_GPU` → the AL2023 accelerated AMI type resolved in task 1.3
    - Preserve the transform structure and both branches so `workload-type: gpu` keeps working
    - The AL2/version pairing is a final-state invariant (Property 11), not a sequencing rule: task 5 and task 6 may be done in either order or concurrently, because no intermediate tree is reconciled against a cluster. The operator-facing rule — AL2023 in place before a *running* cluster moves above 1.32 — is recorded in task 12.5
    - _Requirements: 2.7, 2.9_
    - _Properties: Property 11_

  - [x] 5.2 Change the Karpenter node AMI family
    - In `repos/gitops-system/tools-config/karpenter-config/node-pool.yaml`, set `EC2NodeClass.spec.amiFamily` to `AL2023` and add the now-required `spec.amiSelectorTerms` as `- alias: al2023@latest`
    - These change together: `amiFamily: AL2023` selects the `nodeadm` bootstrap mode
    - _Requirements: 2.8_
    - _Properties: Property 11_

  - [x] 5.3 Run verification checks 1 and 2
    - _Requirements: 10.1, 10.2_

- [x] 6. Kubernetes and Amazon EKS version upgrade
  - [x] 6.1 Set the management cluster version
    - In `initial-setup/config/mgmt-cluster-eksctl.yaml`, set `metadata.version` to `1.36` and set `apiVersion` to the config API version accepted by eksctl `v0.230.0`
    - _Requirements: 2.1, 2.10_

  - [x] 6.2 Rewrite the CloudFormation version parameter and kubectl map
    - In `initial-setup/auto/cfn.yaml`, set the `KubernetesVersion` default to `1.36` and replace `AllowedValues` with the Kubernetes minor versions Amazon EKS lists on standard support, including `1.36` and `1.35` and excluding every extended-support and unlisted version
    - Rewrite the kubectl download `Mappings` block so there is exactly one released patch URL per allowed value, each of the same minor version as the key that selects it
    - Edit the two as a pair — a divergent key set makes the template invalid
    - `AllowedValues` supplies the out-of-set rejection before the management cluster is created
    - _Requirements: 2.5, 2.6, 2.11, 2.12_
    - _Properties: Property 9_

  - [x] 6.3 Set the workload cluster version
    - In `repos/gitops-system/clusters-config/template/def/eks-cluster.yaml`, set `eks-k8s-version` and `mng-k8s-version` both to `1.35`
    - _Requirements: 2.2, 2.3, 2.4_
    - _Properties: Property 10_

  - [x] 6.4 Run verification checks 8 and 12
    - _Requirements: 2.6, 10.12_

- [x] 7. Checkpoint — versions and platform settled
  - Ensure all tests pass, ask the user if questions arise.

- [x] 8. Cluster add-on upgrade
  - [x] 8.1 Migrate Karpenter to v1
    - In `repos/gitops-system/tools/karpenter/karpenter-release.yaml`, pin chart `1.14.1` as an exact version
    - In `repos/gitops-system/tools-config/karpenter-config/node-pool.yaml`: `NodePool` → `karpenter.sh/v1`, `EC2NodeClass` → `karpenter.k8s.aws/v1`, `spec.template.spec.nodeClassRef` → the v1 `group`/`kind`/`name` form, and `disruption.consolidationPolicy` `WhenUnderutilized` → `WhenEmptyOrUnderutilized`
    - The `nodeClassRef` group-version is stated *inside* the `NodePool`, not as its own `apiVersion` — it is easy to miss
    - Follow the upstream v1 migration order rather than applying manifests directly; expect and schedule node replacement
    - _Requirements: 5.1, 5.6, 5.7, 5.8_
    - _Properties: Property 5_

  - [x] 8.2 Upgrade aws-load-balancer-controller 1.4.6 → 3.5.0
    - Pin the chart in `repos/gitops-system/tools/aws-load-balancer-controller/aws-lb-controller-release.yaml`
    - Render the target chart defaults, diff the key set against the `HelmRelease` `spec.values`, and classify each key as unchanged, renamed, or removed; re-express removed keys through whatever key the target accepts for the same behaviour rather than dropping them
    - This spans a controller major bump (v2 → v3) and is one of the two highest-risk migrations in the upgrade
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.9, 5.10_
    - _Properties: Property 6, Property 13_

  - [x] 8.3 Upgrade external-secrets 0.4.4 → 2.10.0
    - Pin the chart in `repos/gitops-system/tools/external-secrets/external-secrets-release.yaml`
    - Apply the same values-schema diff procedure; two major lines are crossed, so substantial renames are expected
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.9, 5.10_
    - _Properties: Property 6, Property 13_

  - [x] 8.4 Upgrade the remaining three charts and the Sealed Secrets label
    - `aws-ebs-csi-driver` `2.30.0` → `2.66.0` in `repos/gitops-system/tools/aws-ebs-csi/aws-ebs-csi-release.yaml`
    - `sealed-secrets` `2.7.1` → `2.20.0` in `repos/gitops-system/tools/sealed-secrets/sealed-secrets-release.yaml`
    - `kubecost` cost-analyzer `2.2.2` → the exact `2.9.x` patch resolved in task 1.3, in `repos/gitops-system/tools/kubecost/kubecost-release.yaml`, together with the `kubecost-modeling` auxiliary image tag the target chart declares
    - Set the label at `repos/gitops-system/clusters-config/template/secrets/namespace.yaml` to the full major.minor.patch of the controller image chart `2.20.0` deploys
    - Apply the values-schema diff procedure to each; pin any separately distributed CRD artifact to the same version as its application chart
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.9, 5.10, 5.11_
    - _Properties: Property 6, Property 8, Property 12, Property 13_

  - [x] 8.5 Add published IAM actions to the add-on policy documents
    - For `repos/gitops-system/tools-config/aws-load-balancer-controller-iam`, `aws-ebs-csi-iam`, `external-secrets-iam`, `karpenter-iam`, and `crossplane-iam`, add actions the maintainers publish for the target version that are absent from our documents
    - Additive only — actions present in ours but absent upstream are left alone
    - _Requirements: 5.5_

  - [x] 8.6 Run verification checks 1, 2, 3, 5 and 9, plus values-schema validation
    - Validate each `HelmRelease` values block against the target chart's published values schema where one exists
    - _Requirements: 10.1, 10.2, 10.3, 10.5, 10.13_
    - _Properties: Property 6_

- [x] 9. Cluster access configuration
  - [x] 9.1 Confirm the provider exposes an access-config field, or record a blocking finding
    - Read the `Cluster` CRD in `crossplane-contrib/provider-aws:v0.59.0` and determine whether an access-config / `authenticationMode` field is settable on `spec.forProvider`
    - If settable, record the field path in the inventory. If not settable, record a **blocking finding** — the requirement is that the mode be stated in the creation request, so a default is not a substitute; do not proceed to 9.2 for the workload cluster path without surfacing this
    - _Requirements: 6.7_

  - [x] 9.2 Set `API_AND_CONFIG_MAP` at creation on both cluster paths
    - In `initial-setup/config/mgmt-cluster-eksctl.yaml`, state `API_AND_CONFIG_MAP` in the eksctl access-config block
    - In `repos/gitops-system/tools-config/crossplane-eks-composition/composition.yaml`, state `API_AND_CONFIG_MAP` on the `eks-cluster` resource's `spec.forProvider` access-config field confirmed in 9.1
    - Must be stated at creation — enabling `API` cannot be reversed, and a cluster created without `CONFIG_MAP` can never gain it
    - Retain `repos/gitops-system/clusters/template/aws-auth.yaml` and both existing `aws-auth` mappings (console IAM entity, Karpenter node role with `system:bootstrappers` and `system:nodes`) on the management and workload cluster paths unchanged
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 6.7, 6.8_

  - [x] 9.3 Run verification checks 1 and 2
    - _Requirements: 10.1, 10.2_

- [x] 10. Bootstrap environment: Cloud9 → VS Code
  - [x] 10.1 Remove Cloud9 from the CloudFormation template
    - In `initial-setup/auto/cfn.yaml`, delete the `AWS::Cloud9::EnvironmentEC2` resource `EKSEnvironment`; the parameters `Cloud9WorkspaceName`, `Cloud9WorkspaceDescription`, `Cloud9IDEInstanceType`, `Cloud9ImageId`, `Cloud9EBSVolumeSize`; `ResizeEBSVolumeDoc`; the `EKSCloud9EnvUrl` output; every `cloud9:*` IAM action; every `CLOUD9_*` environment variable; and the `aws:cloud9:environment` tag lookup with its post-create instance-profile association, reboot, and managed-credentials disable steps
    - Retain `EKSEnvironmentInstanceProfile` and `EKSEnvironmentRole` in function, with the role's `cloud9:*` statements removed
    - Leave unchanged: `BuildProject`, `WaitForStackCreationHandle`/`WaitCondition`, `CustomTriggerBuild`/`TriggerBuildLambda`, `CWLogGroup`, the VPC/subnets/IGW/NAT/route tables/S3+DynamoDB endpoints, all four CodeCommit repositories, `GitOpsUser`, `CodeBuildRole`
    - _Requirements: 2.15_
    - _Properties: Property 16_

  - [x] 10.2 Delete the Cloud9 asset files
    - Delete `initial-setup/config/cloud9-role-permission-policy-template.json`, `initial-setup/img/c9-modify-role.png`, `initial-setup/img/c9instancerole.png`, `initial-setup/img/cloud9-role.png`
    - _Requirements: 2.16_
    - _Properties: Property 16_

  - [x] 10.3 Add the Dev_Environment stack resources
    - In `initial-setup/auto/cfn.yaml`, following the resource pattern of `initial-setup/auto/reference/code-editor.yaml`, add: an `AWS::EC2::Instance` running AL2023 and SSM-managed, with its instance profile and root volume size stated in the instance declaration; a CloudFront distribution; a Secrets Manager generated password; a `CodeEditorSSMDoc` bootstrap document; a health-check Lambda; a security group whose only inbound rule sources the AWS-managed CloudFront origin-facing prefix list for the stack's Region; Dev_Environment instance-type and volume-size parameters; and a stack output carrying the Dev_Environment URL
    - Gate the CodeBuild trigger on the health check: if the environment is not reachable within 20 minutes of the instance entering `running`, fail the stack naming the Dev_Environment as the failing resource and do not run the setup documents
    - State zero literal credential values in the template
    - _Requirements: 2.13, 2.14, 2.18, 2.19, 2.20, 2.21, 2.22, 2.23, 2.24_

  - [x] 10.4 Retarget the SSM orchestration
    - Name the Dev_Environment instance as the Run Command target of all eight retained documents — `InstallK8sClientToolsDoc`, `CloneWorkshopRepo`, `CreateEKSClusterDoc`, `CreateRootSealedSecretsEncryptionKeysDoc`, `SetupCodeCommitSSHAccessDoc`, `CloneCodeCommitReposDoc`, `CreateIAMRoleForCrossplaneDoc`, `ConfigureWorkshopEnvironmentDoc`, `BootstrapGitAndManagementClusterDoc` — plus the new bootstrap document
    - Change CodeBuild instance discovery to read the Dev_Environment instance ID from a stack resource reference instead of the Cloud9 tag lookup; CodeBuild still signals `WaitCondition` on completion
    - _Requirements: 2.17_

  - [x] 10.5 Run verification checks 8, 10 and 12
    - _Requirements: 10.9, 10.12, 2.15, 2.16_
    - _Properties: Property 16_

- [x] 11. Sample application upgrade
  - [x] 11.1 Upgrade the Python API applications
    - In `repos/apps/product-catalog-api/v1/Dockerfile` and `v2/Dockerfile`, replace `python:3.9-slim` with an explicit `python:3.X-slim` whose CPython security-support end date is after the commit date
    - In both `requirements.txt` files, replace `requests==v2.33.0` with an exact PyPI version expressed as digits and separators only, and set `Flask` and `werkzeug` to one identical version across v1 and v2 so a character-by-character comparison of the shared entries reports no difference
    - `requests==v2.33.0` names an unpublished version and fails installation today — this is a break fix, not cleanup
    - _Requirements: 7.1, 7.3, 7.5, 7.6_
    - _Properties: Property 14_

  - [x] 11.2 Upgrade the frontend application
    - In `repos/apps/product-catalog-fe/Dockerfile`, replace `node:14` with an explicit even-numbered Node.js major in Active or Maintenance LTS
    - In `package.json`, set `express` and `body-parser` to ranges whose lower bounds are published on npm (`^4.22.3` and `^1.20.8` are not), and confirm `axios`, `ejs`, `prom-client`, `nodemon` resolve with the bundled npm client
    - Regenerate `package-lock.json` after the ranges settle so every resolved version satisfies its range and every declared dependency is present
    - Use a lockfile-based install command whose options the bundled npm version accepts
    - _Requirements: 7.2, 7.4, 7.7, 7.8_

  - [x] 11.3 Replace mutable image tags in deployment manifests
    - Replace `:latest` with an immutable tag in `repos/apps-manifests/product-catalog-fe-manifests/kubernetes/overlays/prod/deployment.yaml` and `overlays/staging/deployment.yaml`, and check the API manifests' prod and staging overlays for the same
    - _Requirements: 7.9_
    - _Properties: Property 13_

  - [x] 11.4 Run verification checks 6, 7 and 13
    - _Requirements: 7.10, 7.11, 7.12, 7.13, 10.6, 10.7_

- [x] 12. Documentation alignment
  - [x] 12.1 Rewrite `initial-setup/README.md`
    - Restate every version as its inventory `target`: kubectl `1.24.7` → a `1.36` patch, `yq v4.24.5` → `v4.53.6`, `kubeseal v0.19.4` → the controller minor from sealed-secrets chart `2.20.0`, Flux CLI `0.35.0` → the same `2.9` release pinned in `cfn.yaml`
    - Replace the Cloud9 workspace preparation section with steps for opening the Dev_Environment, including obtaining the URL from the stack output and the credential from Secrets Manager, and state the Dev_Environment OS name and version in place of the Ubuntu 18.04 description
    - Delete the steps, screenshots, and policy-template references for creating and attaching the Cloud9 instance role, and renumber the remaining steps of those procedures consecutively
    - State that the manual setup path may be run either from the Dev_Environment or from the reader's own terminal, and list the tools that terminal requires
    - Resolve the documented `gitops-system/tools-config/eks-console/{role,role-binding}.yaml` step: no such directory exists, and console access is already granted through `aws-auth`. Either point at the equivalent resource the repository provides or omit the step where there is no equivalent, and record the decision in the migration log (task 12.5)
    - _Requirements: 9.1, 9.2, 9.4, 9.5, 9.11, 9.12, 9.13, 9.15, 9.16, 5.12, 3.7_
    - _Properties: Property 15_

  - [x] 12.2 Update the remaining documentation files
    - In `README.md`, `repos/gitops-system/README.md`, `bin/README.md`, and the files under `initial-setup/doc/`, restate every version as its inventory `target` and reference only paths present in the repository
    - Name `crossplane-contrib/provider-aws` as the AWS provider package the platform references after the upgrade, and link to its authentication guidance with a resolvable URL
    - Link to the upgrade notes file created in task 12.5
    - _Requirements: 9.1, 9.2, 9.3, 9.9, 9.10_
    - _Properties: Property 15_

  - [x] 12.3 Update the cluster upgrade scenario
    - In `scenarios.md`, state the upgrade as `1.35` → `1.36` and state no other Kubernetes version number in that scenario
    - State that the workload cluster version is one minor below the management cluster version by intent, to give this scenario a version gap to exercise
    - _Requirements: 9.7, 9.8_

  - [x] 12.4 Update the clean-up procedure
    - In `clean-up/README.md`, add the Dev_Environment deletion step and remove the Cloud9 deletion step
    - _Requirements: 9.14_

  - [x] 12.5 Write the migration log and the four rationale notes
    - Create `initial-setup/doc/upgrade-notes.md` containing, for each Pinned_Component whose upgrade required a manifest or configuration change, the component name, the change made, and a resolvable upstream migration URL — covering at minimum the Flux beta API removal, the Karpenter v1 migration, the AL2 → AL2023 change, and the Crossplane platform bumps
    - Include the live-upgrade ordering guidance, addressed to an operator rolling this upgrade onto running infrastructure and stated as such — these constraints do not apply to editing this repository, where intermediate states are inert: move node groups and `EC2NodeClass` resources to AL2023 **before** raising a running cluster's Kubernetes version above `1.32`, since above that boundary Amazon EKS publishes no AL2 AMI and a node group still declaring `AL2_x86_64` cannot be created or replaced; apply the `gotk-components.yaml` change and the consuming Flux custom resource changes **together, in one reconciliation**, because the components alone leave existing beta resources unserved and the resources alone fail admission against the old CRDs; follow the upstream Karpenter v1 migration order rather than applying the v1 manifests directly, and schedule the node replacement that `amiFamily: AL2023` triggers; and note that `authenticationMode` cannot be changed to add `CONFIG_MAP` after creation, so an existing cluster created without it cannot be brought onto the retained `aws-auth` path and must be recreated
    - Include the four mandated notes: the workload/management version gap is intentional; Crossplane v2 is out of scope, naming composite resource connection details, native patch-and-transform composition, and `ControllerConfig` as the capabilities it removes, with a link to the v2 upgrade guide; `aws-auth` is deprecated but retained, linking the EKS guidance, recording access entries as deferred, and stating both irreversibility constraints; and the development environment changed because AWS closed Cloud9 to new customers, with a link stating that unavailability
    - Record the remaining deferred items — `ControllerConfig` → `DeploymentRuntimeConfig` and native → Pipeline-mode `Composition` — as future work
    - Record the `eks-console/` path resolution decision from task 12.1
    - _Requirements: 9.6, 9.18, 4.9, 4.11, 4.20, 6.10_

  - [x] 12.6 Run the full credential-free suite
    - Run `verify/run.sh` end to end; checks 1–13 must all pass within the 600-second budget and checks 14–15 must report as skipped with a reason
    - Check 11 must report zero documented version strings diverging from the inventory and zero referenced paths absent from the repository
    - _Requirements: 9.17, 10.1, 10.14, 10.17_
    - _Properties: Property 15, Property 16_

- [x] 13. Checkpoint — offline suite green
  - Ensure all tests pass, ask the user if questions arise.

- [-] 14. End-to-end run — REQUIRES AN AWS ACCOUNT
  - [-]* 14.1 Execute verification checks 14 and 15 against a real AWS account
    - **This is a manual/integration run, not an offline coding task.** It is the only step that cannot be validated offline; it confirms rather than discovers.
    - This is also where the category-4 live-cluster deployment ordering recorded in task 12.5 is exercised — AL2023 before raising a running cluster above `1.32`, the Flux components and resources applied in one reconciliation, the Karpenter v1 upstream migration order, and `authenticationMode` stated at creation.
    - Check 14: assert Target_Kubernetes_Version and Workload_Kubernetes_Version are both in EKS standard support on the day the check runs
    - Check 15: assert the documented flow bounds — management cluster `ACTIVE` within 30 minutes; hub tool reconciliations ready within 15 minutes; sealed secret unsealed within 60 seconds; workload cluster composite `Ready`/`Synced` within 45 minutes; Flux installed into the workload cluster within 15 minutes; workload add-ons ready within 20 minutes; application pods ready within 10 minutes; DynamoDB managed resource ready within 10 minutes; control plane and node group upgrades within 60 minutes each; teardown within 45 minutes
    - Confirm `bin/*.sh` generated manifests declare only served `apiVersion` values with no unrecognized-kind or deprecation warning, and that every `flux-system` `Kustomization` reaches `Ready=True` within 600 seconds
    - Validate the Crossplane provider bump on a throwaway cluster before touching an environment with live workload clusters
    - _Requirements: 3.9, 8.1, 8.2, 8.3, 8.4, 8.5, 8.6, 8.7, 8.8, 8.9, 8.10, 8.11, 8.12, 10.8_
    - _Properties: Property 10, Property 11, Property 18_

## Notes

- Tasks marked with `*` are optional and can be skipped for a faster pass; they are the verification runs and the AWS-account integration step.
- Task 3.1 stays one sub-task because it is one logical change across four edit surfaces, and splitting it invites landing half of it and leaving the finished tree inconsistent. Its consistency requirement is Correctness Properties 1–3, decided by verification check 2, not by commit granularity. The single-reconciliation rule is operator guidance in task 12.5.
- Task 1 gates every other task: no repository file is edited before its target version is recorded in the inventory with a source URL and consulted date. This is a real data dependency, not a stylistic one.
- Tasks 5 and 6 are unordered relative to each other. The rule that no Kubernetes version above 1.32 may be paired with an AL2 AMI type is a final-state invariant (Property 11) enforced by the verification suite, not an edit-sequencing rule.
- Same-file write serialization matters only under parallel execution, where it prevents merge conflicts; it has no bearing on correctness and imposes nothing sequentially. Five files are written by more than one task: `initial-setup/auto/cfn.yaml` (tasks 3.1, 6.2, 10.1, 10.3, 10.4), `tools-config/crossplane-eks-composition/composition.yaml` (4.4, 5.1, 9.2), `tools-config/karpenter-config/node-pool.yaml` (5.2, 8.1), `initial-setup/config/mgmt-cluster-eksctl.yaml` (6.1, 9.2), and `version-inventory.yaml` (1.1, 1.2, 1.3, 4.1, 4.2, 9.1). Whichever task lands second must preserve what the first wrote.
- Tasks 4.1, 4.2 and 9.1 are confirmations against the pinned provider package, each recording a decision in the inventory. Task 9.1 can produce a blocking finding.
- The correctness properties in the design are discharged by exhaustive enumeration in `verify/`, not by generative testing — every property's domain is fully present in the repository or in a pinned artifact, so the numbered checks visit it in full.
- The four non-goals are documented in task 12.5 as deferred work and are not implemented anywhere in this plan.

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "2.1"] },
    { "id": 1, "tasks": ["1.2", "2.2", "2.3", "2.4", "2.5", "2.6", "2.7"] },
    { "id": 2, "tasks": ["1.3"] },
    { "id": 3, "tasks": ["3.1", "4.3", "5.1", "5.2", "6.1", "6.3", "8.2", "8.3", "8.4", "8.5", "9.1", "10.2", "11.1", "11.2", "11.3"] },
    { "id": 4, "tasks": ["3.2", "4.1", "5.3", "6.2", "8.1", "9.2", "11.4"] },
    { "id": 5, "tasks": ["4.2", "6.4", "8.6", "9.3", "10.1"] },
    { "id": 6, "tasks": ["4.4", "10.3"] },
    { "id": 7, "tasks": ["4.5", "10.4"] },
    { "id": 8, "tasks": ["10.5", "12.1", "12.3", "12.4"] },
    { "id": 9, "tasks": ["12.5"] },
    { "id": 10, "tasks": ["12.2"] },
    { "id": 11, "tasks": ["12.6"] },
    { "id": 12, "tasks": ["14.1"] }
  ]
}
```
