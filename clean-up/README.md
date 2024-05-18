# Clean-up
1. Un-deploy the applications/microservices on the workload clusters by removing the resources listed in `gitops-workloads/<cluster-name>/kustomization.yaml`
2. Un-deploy the tools installed in the workload clusters by removing the resources listed in `gitops-system/clusters/<cluster-name>/kustomization.yaml`. Wait for the tools to be uninstalled before you proceed to the next step.
3. Un-deploy the workload clusters by removing the resources listed in `gitops-system/clusters-config/kustomization.yaml`. Wait for all workload clusters to be fully deleted (including corresponding VPC) before you proceed to the next step.
4. Un-deploy the tools installed in the management cluster by removing the resources listed in `gitops-system/clusters/mgmt/kustomization.yaml` (except `./flux-system`). Wait for the tools to be uninstalled before you proceed to the next step.
5. Un-deploy the management cluster.
    ```
    eksctl delete cluster --name mgmt --region $AWS_REGION
    ```
    
6. Remove the GitHub repos or AWS CodeCommit repos you created.
    - For GitHub you can use:
        ```
        gh repo delete --confirm product-catalog-api-manifests
        gh repo delete --confirm product-catalog-fe-manifests
        gh repo delete --confirm gitops-workloads
        gh repo delete --confirm gitops-system  
        ```
    - If you performed the initial setup using CloudFormation, you can skip this step - the AWS CodeCommit repos will be deleted as part of the CloudFormation stack deletion.
7. Remove the secret in Secrets Manager.
    ```
    aws secretsmanager delete-secret --secret-id sealed-secrets --force-delete-without-recovery
    ```

8. Remove the crossplane role
    ```
    POLICY_ARN=$(aws iam list-attached-role-policies --role-name crossplane-role --query AttachedPolicies[0].PolicyArn --output text)
    aws iam detach-role-policy --role-name crossplane-role --policy-arn $POLICY_ARN
    aws iam delete-policy --policy-arn $POLICY_ARN 
    aws iam delete-role --role-name crossplane-role
    ```

9. Remove DynamoDB tables created by the `product-catalog-api` application. You can list tables
starting with "product-" using:
    ```
    aws dynamodb list-tables --query "TableNames[?starts_with(@, 'prod') == \`true\`]"
    ```
    Then delete individual tables using:
    ```
    aws dynamodb delete-table --table-name <table-name>
    ```
10. Delete the IAM user that was used to interact with the CodeCommit repos from the Cloud9 environment, and from the EKS clusters by the Flux source controller. Also, delete the associated IAM policy. Skip this step if you used CloudFormation to perform the initial setup.

11. If you used CloudFormation to perform the initial setup, delete the corresponding CloudFormation stack:
    ```
    aws cloudformation delete-stack --stack-name gitops-initial-setup
    ```
