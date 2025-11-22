# ECS Fargate App bla

Deploy a containerized app on ECS Fargate with an ALB, VPC, ECR, and all required infrastructure - fully wired and production-ready with Terraform.

# Quick Start Guide

Deploy a containerized application on AWS ECS Fargate with automated infrastructure provisioning. This guide provides step-by-step instructions with validation commands and troubleshooting guidance.

## Prerequisites Checklist

Before you start, ensure you have:

- [ ] AWS CLI installed and configured (`aws --version`)
- [ ] Terraform >= 1.6 installed (`terraform version`)
- [ ] Docker installed (`docker --version`)
- [ ] AWS credentials configured (`aws sts get-caller-identity`)
- [ ] Appropriate AWS permissions (ECS, ECR, VPC, ALB, IAM, CloudWatch)

## Architecture Overview

This template deploys:

- **VPC** with public and private subnets across multiple AZs
- **Application Load Balancer (ALB)** for HTTP traffic distribution
- **ECS Fargate Service** for serverless container orchestration
- **ECR Repository** for Docker image storage
- **Security Groups** with least-privilege access
- **IAM Roles** for ECS task execution
- **CloudWatch Logs** for application monitoring

## Step 1: Verify Prerequisites

Check that all required tools are installed:

```bash
make bootstrap
```

**Expected Output:**
```
✓ Terraform found: 1.6.0
✓ Required tools are installed
```

## Step 2: Configure Your Environment

Edit `envs/dev/terraform.tfvars`:

```hcl
# Basic Configuration
aws_region  = "us-east-1"           # CHANGE THIS
environment = "dev"
app_name    = "myapp"               # CHANGE THIS (used for resource naming)

# VPC Configuration
vpc_cidr = "10.0.0.0/16"

# ECS Configuration
task_cpu      = "256"               # 0.25 vCPU
task_memory   = "512"               # 512 MB
desired_count = 1                   # Number of tasks

# Container Configuration
container_port = 80                 # Port your app listens on
image_tag      = "latest"

# Features
enable_container_insights = false   # CloudWatch Container Insights (extra cost)
enable_cloudwatch_logs    = true    # Application logs

# Auto Scaling (optional)
enable_autoscaling  = false
min_capacity        = 1
max_capacity        = 4
cpu_target_value    = 70            # Scale up when CPU > 70%
memory_target_value = 80            # Scale up when memory > 80%
```

**Key Configuration Decisions:**

| Environment | task_cpu | task_memory | desired_count | enable_autoscaling |
|-------------|----------|-------------|---------------|-------------------|
| **dev**     | 256      | 512         | 1             | false             |
| **staging** | 512      | 1024        | 2             | true              |
| **prod**    | 1024     | 2048        | 3             | true              |

## Step 3: Customize Your Application

Replace the sample Flask app with your application:

```bash
cd app/
# Replace app.py with your application code
# Update Dockerfile if needed
```

**Important:** Ensure your Dockerfile:
- Exposes the port specified in `container_port`
- Runs the application on `0.0.0.0` (not localhost)
- Includes a health check endpoint (optional but recommended)

**Example Dockerfile validation:**
```bash
docker build -t test-app .
docker run -p 80:80 test-app
# Test in browser: http://localhost
```

## Step 4: Initialize Terraform

```bash
make init ENV=dev
```

**Expected Output:**
```
Initializing Terraform for dev environment...
✓ Terraform initialized
```

**What This Does:**
- Downloads required Terraform providers
- Configures backend for state storage
- Prepares modules

## Step 5: Plan Infrastructure Deployment

```bash
make plan ENV=dev
```

**Expected Output:**
```
Planning Terraform for dev environment...
Plan: 25 to add, 0 to change, 0 to destroy.
✓ Plan complete
```

**Review the plan carefully:**
- Check resource names match your configuration
- Verify VPC CIDR doesn't conflict with existing networks
- Confirm no unexpected deletions

## Step 6: Deploy Infrastructure

```bash
make apply ENV=dev
```

**Expected Output:**
```
Applying Terraform for dev environment...
...
Apply complete! Resources: 25 added, 0 changed, 0 destroyed.
✓ Infrastructure deployed
```

**What Gets Created:**
- VPC with 2 public and 2 private subnets
- Internet Gateway and NAT Gateway
- Application Load Balancer
- ECR Repository
- ECS Cluster
- ECS Service (will be in "PENDING" state until image is pushed)
- Security Groups
- IAM Roles and Policies
- CloudWatch Log Groups

## Step 7: Build and Push Docker Image

Get the ECR repository URL from Terraform outputs:

```bash
cd infra
terraform output ecr_repository_url
```

Build and push your Docker image:

```bash
# Return to project root
cd ..

# Build Docker image
make build

# Login to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $(cd infra && terraform output -raw ecr_repository_url)

# Push image to ECR
make push ECR_REPOSITORY_URL=$(cd infra && terraform output -raw ecr_repository_url)
```

**Expected Output:**
```
The push refers to repository [123456789012.dkr.ecr.us-east-1.amazonaws.com/myapp]
latest: digest: sha256:abc123... size: 1234
```

## Step 8: Verify Deployment

Check ECS service status:

```bash
aws ecs describe-services \
  --cluster $(cd infra && terraform output -raw ecs_cluster_name) \
  --services $(cd infra && terraform output -raw ecs_service_name) \
  --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount}' \
  --output table
```

**Expected Output:**
```
--------------------------------------------
|           DescribeServices              |
+----------+----------+-------------------+
| Desired  | Running  | Status            |
+----------+----------+-------------------+
| 1        | 1        | ACTIVE            |
+----------+----------+-------------------+
```

Check task status:

```bash
aws ecs list-tasks \
  --cluster $(cd infra && terraform output -raw ecs_cluster_name) \
  --service-name $(cd infra && terraform output -raw ecs_service_name)
```

## Step 9: Access Your Application

Get the ALB URL:

```bash
cd infra
terraform output alb_dns_name
```

**Example Output:**
```
"alb1-123456789.us-east-1.elb.amazonaws.com"
```

Visit the URL in your browser:
```bash
open http://$(cd infra && terraform output -raw alb_dns_name)
```

**Note:** It may take 1-2 minutes for the ALB health checks to pass and start routing traffic.

## Common Operations

### View Application Logs

```bash
aws logs tail /ecs/$(cd infra && terraform output -raw ecs_cluster_name) --follow
```

### Update Application (Deploy New Version)

```bash
# 1. Build new image
make build

# 2. Push to ECR
make push ECR_REPOSITORY_URL=$(cd infra && terraform output -raw ecr_repository_url)

# 3. Force new deployment
aws ecs update-service \
  --cluster $(cd infra && terraform output -raw ecs_cluster_name) \
  --service $(cd infra && terraform output -raw ecs_service_name) \
  --force-new-deployment
```

### Scale Service

```bash
# Scale to 3 tasks
aws ecs update-service \
  --cluster $(cd infra && terraform output -raw ecs_cluster_name) \
  --service $(cd infra && terraform output -raw ecs_service_name) \
  --desired-count 3
```

### View All Outputs

```bash
make outputs ENV=dev
```

## Troubleshooting

### Issue: Tasks Fail to Start

**Check task logs:**
```bash
aws logs tail /ecs/$(cd infra && terraform output -raw ecs_cluster_name) --since 10m
```

**Common causes:**
- Docker image doesn't exist in ECR
- Image pull errors (check IAM permissions)
- Application crashes on startup
- Port mismatch between Dockerfile EXPOSE and task definition

**Solution:**
1. Verify image exists: `aws ecr describe-images --repository-name myapp`
2. Check ECS task execution role has `AmazonECSTaskExecutionRolePolicy`
3. Test Docker image locally first

### Issue: Cannot Access Application

**Check ALB target health:**
```bash
aws elbv2 describe-target-health \
  --target-group-arn $(cd infra && terraform output -raw target_group_arn)
```

**Common causes:**
- Health check failing (tasks not responding on port 80)
- Security group not allowing traffic
- Tasks not running

**Solution:**
1. Ensure app listens on `0.0.0.0:80` (not `localhost`)
2. Check security groups allow port 80
3. Verify tasks are in RUNNING state

### Issue: Out of Memory / High CPU

**Check CloudWatch metrics:**
```bash
# View service metrics in AWS Console
echo "https://console.aws.amazon.com/ecs/home?region=us-east-1#/clusters/$(cd infra && terraform output -raw ecs_cluster_name)/services/$(cd infra && terraform output -raw ecs_service_name)/metrics"
```

**Solution:**
1. Increase `task_cpu` and `task_memory` in `terraform.tfvars`
2. Run `make apply ENV=dev`
3. Force new deployment

### Issue: Image Pull Errors

**Error:** `CannotPullContainerError: Error response from daemon`

**Solution:**
```bash
# Verify ECR repository exists
aws ecr describe-repositories --repository-names myapp

# Verify image exists
aws ecr describe-images --repository-name myapp

# Check task execution role permissions
aws iam get-role-policy \
  --role-name app-exec \
  --policy-name AmazonECSTaskExecutionRolePolicy
```

## Cleanup

To destroy all resources and avoid ongoing costs:

```bash
make destroy ENV=dev
```

**Warning:** This will permanently delete:
- ECS Service and Tasks
- Load Balancer
- VPC and all networking
- CloudWatch Logs
- **ECR Repository and all images**

Type `yes` when prompted to confirm.

## Next Steps

- **Production Readiness**: Review [DEPLOYMENT.md](./DEPLOYMENT.md) for production best practices
- **CI/CD Integration**: See [examples/deployment-examples/cicd-example.md](./examples/deployment-examples/cicd-example.md)
- **Environment Variables**: See [examples/deployment-examples/env-vars-example.md](./examples/deployment-examples/env-vars-example.md)
- **HTTPS Setup**: Add AWS Certificate Manager and update ALB listener
- **Custom Domain**: Configure Route53 to point to ALB
- **Auto-scaling**: Enable in `terraform.tfvars` for staging/prod
- **Monitoring**: Enable Container Insights and set up CloudWatch alarms
- **Security**: Run `make security` to scan for security issues

## Cost Estimation

**Development Environment (dev):**
- ECS Fargate (256 CPU, 512 MB): ~$10/month
- ALB: ~$20/month
- NAT Gateway: ~$35/month
- ECR Storage: ~$0.10/GB/month
- CloudWatch Logs: ~$0.50/GB ingested
- **Total: ~$65-70/month**

**Cost Optimization Tips:**
- Use shared NAT Gateway (already configured)
- Set log retention to 7 days for dev
- Delete unused ECR images regularly
- Stop non-essential environments when not in use

## Support

For issues or questions:
- Check [DEPLOYMENT.md](./DEPLOYMENT.md) for detailed documentation
- Review [examples/](./examples/) for common scenarios
- Run `make help` to see all available commands

---

*This template is maintained by Senora.dev.*


## Environment Variables

This project uses environment-specific variable files in the `envs/` directory.

### dev
Variables are stored in `envs/dev/terraform.tfvars`

### bla
Variables are stored in `envs/bla/terraform.tfvars`

### prod
Variables are stored in `envs/prod/terraform.tfvars`



## GitHub Actions CI/CD

This project includes automated Terraform validation via GitHub Actions.

### Required GitHub Secrets

Configure these in Settings > Secrets > Actions:

- `AWS_ACCESS_KEY_ID`: Your AWS Access Key
- `AWS_SECRET_ACCESS_KEY`: Your AWS Secret Key
- `TF_STATE_BUCKET`: `senora-terraform-state-ecs-fargate-app-bla-6921dc5effacbeb416b05c66`
- `TF_STATE_KEY`: `ecs-fargate-app-bla/terraform.tfstate`


---
*Generated by [Senora](https://senora.dev)*
