# Clean-up
1. Un-deploy the applications/microservices on the workload clusters by removing the resources listed in ```gitops-workloads/\<cluster-name\>/kustomization.yaml```
2. Un-deploy the workload clusters by removing the resources listed in ```gitops-system/clusters-config/kustomization.yaml```
3. Un-deploy the management cluster.
```
eksctl delete cluster --name mgmt --region eu-west-1
```
4. Remove the GitHub repos or AWS CodeCommit repos you created.