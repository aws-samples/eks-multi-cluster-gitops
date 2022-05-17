# Build Multi-Cluster GitOps system using Amazon EKS, Flux CD, and Crossplane
## Introduction
GitOps is a new approach for implementing continuous delivery that was pioneered in 2017. Since then, a lot of development happened in this space — several GitOps tools got released, and many organizations started adopting this new approach in their environment.

Organisation varies in their structure and complexity — large ones tend to have multiple clusters, one for each environment, and if they have multiple departments, they might even have a cluster per department and per environment. They want to see how GitOps can be applied in multi-cluster environments. Also, organisations usually have separate teams for managing technology platforms, in addition to the development teams who focus on producing code that address business problems/opportunities. Those teams have different uses cases — application development teams want to deploy their applications into various clusters, these applications consist of native K8s resources (e.g. Deployment, Service, ConfigMap, etc.), and other non-K8s resources as well (e.g. DynamoDB table, SQS queue, etc.). Platform teams want to provision new clusters and bootstrap them with tooling, decommission existing clusters, upgrade clusters, upgrade the tooling consistently across all clusters, etc. 

This repo contains a sample implementation of a multi-cluster GitOps system that addresses the application development teams use cases, as well as the platform teams use cases. It extends GitOps, not only to cover the deployment and the management of the native K8s resources, and non-K8s resources (e.g. DynamoDB table, SQS queue, etc.), but also to cover the deployment and the management of clusters. It provides guidance about how you can structure your Git repos respecting the responsibilities of different teams, and allowing them to collaborate. It also provides guidance about managing secrets, which is one of the challenging areas in GitOps.

## Architecture
A hub/spoke model is used to implement the multi-cluster GitOps. As part of the initial setup, an EKS cluster — the management cluster — is manually created using eksctl, and bootstrapped. Then, the other EKS clusters — workload clusters — are created dynamically by the management cluster using GitOps. The clusters bootstrapping and the deployment of various tools and controllers are also performed using GitOps.

This solution uses FluxCD as a GitOps tool, and uses Crossplane as an infrastructure controller. It also uses Sealed Secrets and External Secrets Operator for secrets management — more details about that exist in the following sections.

The architecture of the solution is depicted in the following diagram:
![Image of Clone button](doc/images/architecture.png)

After the initial setup, the Flux controller in the management deploys other controllers that are required in the management cluster — this includes External Secrets Operator, Sealed Secrets, and Crossplane. The Flux controller also synchronizes the workloads clusters definition that exist in Git into the management clusters. Then, Crossplane picks up these definitions, and creates the workload clusters. The Flux controller on the management cluster is also responsible for bootstrapping the provisioned workload cluster with its own Flux controller, and the pre-requisites for that.

The Flux controller on each of the workload clusters deploys other tools required on the cluster (e.g. Crossplane), and the workloads (applications, microservices, ...) meant to be deployed on the cluster, as defined in Git. The workloads typically consist of standard Kubernetes resources (e.g. Deployment, Service, ConfigMap, Secret, etc.), and infrastructure resources as well (e.g. DynamoDB table, SQS queue, RDS instance, etc.) that are required for the workload to fully function.

One of the architectural decisions made is to deploy a separate Flux and Crossplane controller on each of the workload clusters, rather than having a central Flux and Crossplane controllers in the management clusters that server all the clusters. The key reason behind that is to reduce dependency on the management cluster, and to increase the scalability of the solution — single/central set of controllers in the management cluster would lead to less scalable solution, compared to separate set of controllers per cluster.

### Git Repositories
The table below lists the proposed repos:

Local Path | Git Repo Name | Owner | Description |
--- | --- | --- | --- |
| `gitops-system` | `gitops-system` | Platform team | This repo contains the manifests for all workload clusters, the manifests for the tools installed on the clusters. It also contains the directories that are synced by the Flux controller of each cluster. While this repo is owned by the platform team, application teams may raise pull requests for new clusters they want to create, or changes on existing cluster they want to implement. Platform team reviews and merges pull requests. See the [README][gitops-system-readme] for more detailed information about its contents. |
| `app-manifests/payment-app` | `payment-app-manifests` | Application Team | This represents the application repository for an imaginary service named `payment-app`. It contains a Kustomization and overlays for the `payment-app` application resources and the IaC resources. |
| `gitops-workloads` | `gitops-workloads` | Governance team | This repo connects the repos above — it specifies which applications are deployed on which clusters i.e. for deploying a new application or microservice into a cluster, you go to the folder corresponding to the cluster, and add the manifests required for having a Flux Kustomization that syncs the application repo to the target cluster. This repo may be owned by a central governance team, where application teams raise a pull request for deploying their application to a cluster, and the central governance team reviews and merges the pull request. Also, organizations may choose to reduce governance overhead, and keep this repo open for application teams to directly commit into it the manifests required for deploying their application into a cluster. In that case, it is important to deploy and enable the cluster auto scaler on the clusters to automatically scales out and in, based on the workloads deployed into it. |

**Note:**
The `initial-setup` directory is meant for a one-time initialisation of the management cluster and does not need to be placed into its own repository. 

[gitops-system-readme]: ./repos/gitops-system/README.md

### Secrets Management
One of the key challenges in GitOps is managing secrets. GitOps entails storing the target state of the system in Git — this covers all the manifests required for describing the target state of the system, including secrets/credentials used for different purposes e.g. username/password used for connecting to a database, or an external service, or even the credentials used by the Flux controller for connecting to Git repos, or the AWS credentials that are required for infrastructure controllers like Crossplane. Such credentials cannot be stored in Git in its plain form, it has to be encrypted. For that purpose, the solution includes Sealed Secrets. The secret information that needs to be deployed into the clusters is first encrypted by the user, and a corresponding SealedSecret resource is created — that is what gets committed into Git. The Sealed Secret controller is then responsible for decrypting the SealedSecret resources deployed via GitOps, and transforming them to a Secret resource, and can be referenced by other resources.

Sealed Secrets itself requires public/private keys that are used for encrypting/decrypting secrets. This can be auto-generated by Sealed Secrets controller at start up time, or predefined using a Secret with specific label. A decision was made to predefine the public/private keys used by Sealed Secrets. Otherwise, it would have been challenging to complete the creation and bootstrapping of new workload clusters using GitOps without manual intervention/customisation. The reason is that bootstrapping the workload cluster involves deploying Flux controller, and the Flux controller requires credentials to be able to connect to Git for synchronization. If the public/key used for encrypting/decrypting the Git credentials are auto generated at deployment time, then the process will have to be split into multiple parts with manual intervention or custom implementation — the first part is the creation of the cluster, and the deployment of Sealed Secrets controller into it. Then, the generated public key needs to be retrieved and used for re-encrypting the Git credentials. The re-encrypted credentials need to be committed into Git. Then, the last part would be deploying the Flux controller.

The pre-defined public/private key pair for Sealed Secrets is created as part of the initial setup, and stored in AWS Secrets Manager. External Secrets Operator is used for retrieving the keys in AWS Secrets Manager, and creating a Secret in the cluster that contains the keys, and has the label required for Sealed Secrets.

This repository contains the configuration of the management cluster and Kubernetes manifests representing the workload clusters, their configuration and the applications running within them. While these are represented as directories within this single repositories, the system assumes that they are split into multiple separate repositories - which allows for finer-grained permissions and version control over each separate part. The directories should be divided into the following repositories:

## Deployment
Please refer to [the initial setup](./initial-setup) for deploying the system. Also refer to [scenarios](./scenarios.md) for the instructions related to various scenarios (e.g. creating a new workload cluster, deleting a workload cluster, onboarding a new microservice/application and deploying it to one or more of the workload clusters).

Please refer to [Clean-up](./clean-up) for un-deploying the system.

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the LICENSE file.

