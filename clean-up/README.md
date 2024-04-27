# Clean-up
1. Un-deploy the applications/microservices on the workload clusters by removing the resources listed in ```gitops-workloads/\<cluster-name\>/kustomization.yaml```
2. Un-deploy the workload clusters by removing the resources listed in ```gitops-system/clusters-config/kustomization.yaml```
3. Un-deploy the management cluster.
    ```
    eksctl delete cluster --name mgmt --region $AWS_REGION
    ```
    
4. Remove the GitHub repos or AWS CodeCommit repos you created.
    - For GitHub you can use:
        ```
        gh repo delete --confirm product-catalog-api-manifests
        gh repo delete --confirm product-catalog-fe-manifests
        gh repo delete --confirm gitops-workloads
        gh repo delete --confirm gitops-system  
        ```
5. Remove the secret in Secrets Manager.
    ```
    aws secretsmanager delete-secret --secret-id sealed-secrets --force-delete-without-recovery
    ```

6. Remove the crossplane role
    ```
    POLICY_ARN=$(aws iam list-attached-role-policies --role-name crossplane-role --query AttachedPolicies[0].PolicyArn --output text)
    aws iam detach-role-policy --role-name crossplane-role --policy-arn $POLICY_ARN
    aws iam delete-policy --policy-arn $POLICY_ARN 
    aws iam delete-role --role-name crossplane-role
    ```

7. Remove DynamoDB tables created by the `product-catalog-api` application. You can list tables
starting with "product-" using:
    ```
    aws dynamodb list-tables --query "TableNames[?starts_with(@, 'prod') == \`true\`]"
    ```
    Then delete individual tables using:
    ```
    aws dynamodb delete-table --table-name <table-name>
    ```
8. Delete the IAM that was used to interact with the CodeCommit repos from the Cloud9 environment, and from the EKS clusters by the Flux source controller. Also, delete the associated IAM policy

    ```
    POLICY_ARN=$(aws iam list-attached-role-policies --role-name crossplane-role --query AttachedPolicies[0].PolicyArn --output text)
    aws iam detach-role-policy --role-name crossplane-role --policy-arn $POLICY_ARN
    aws iam delete-policy --policy-arn $POLICY_ARN 
    aws iam delete-role --role-name crossplane-role
    ```
