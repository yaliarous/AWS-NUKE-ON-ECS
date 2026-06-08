
# Project purpose

Do you have an AWS lab/test account and worry about leaving resources running and getting a huge bill? This project helps you delete all resources in a target account on a schedule.

# Architecture

An ECS task running aws-nuke is triggered every midnight in AWS account A and deletes resources in a target account (AWS account B).

**WARNING: aws-nuke irreversibly deletes resources. Use only on disposable/test accounts and verify configuration before running.**

# Quickstart

1) Create an ECR repository in account A:

```
aws ecr create-repository \
    --repository-name aws-nuke \
    --region eu-west-1 --profile account-a
```

2) Build and push the Docker image to account A:

```
docker build . -t {account_a_id}.dkr.ecr.eu-west-1.amazonaws.com/aws-nuke:latest --no-cache
aws ecr --profile account-a get-login-password --region eu-west-1 | docker login --username AWS --password-stdin {account_a_id}.dkr.ecr.eu-west-1.amazonaws.com
docker push {account_a_id}.dkr.ecr.eu-west-1.amazonaws.com/aws-nuke:latest
```

3) Create an IAM role on the target account (account B):

Create an IAM role aws-nuke-role in account B with a trust policy that allows assume-role from account A. Then attach the AdministratorAccess policy to this role.

4) Deploy with Terraform
```
terraform init
terraform apply  -var='SOURCE_ACCOUNT_ID={account_a_id}' -var='TARGET_ACCOUNT_ID={account_b_id}' 
```


# Cost 

With daily run of 10 minutes the estimated cost is ~$0.07/month

# Failed tasks notification:

To receive an email notification when AWS-NUKE fail, create AWS Eventbridge rule with the following event pattern and set SNS as target
```
{
  "source": ["aws.ecs"],
  "detail-type": ["ECS Task State Change"],
  "detail": {
    "desiredStatus": ["STOPPED"],
    "lastStatus": ["STOPPED"],
    "containers": {
      "exitCode": [{
        "anything-but": [0]
      }]
    }
  }
}
```


# Manual Invoke for testing

aws ecs run-task \
  --profile account-a \
  --cluster resource-cleanup-cluster \
  --task-definition resource-cleanup \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=["$(terraform output -raw first_subnet_id)"
],securityGroups=["$(terraform output -raw security_group_id)"],assignPublicIp=ENABLED}" \
  --region eu-west-1 



