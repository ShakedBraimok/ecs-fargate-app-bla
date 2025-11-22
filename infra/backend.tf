terraform {
  backend "s3" {
    # Replace with your S3 bucket name for Terraform state
    bucket = "senora-terraform-state-ecs-fargate-app-bla-6921dc5effacbeb416b05c66"
    
    # This is the path to the state file inside the bucket
    key    = "ecs-fargate-app-bla/terraform.tfstate"

    # Replace with the AWS region of your bucket
    region = "eu-west-1"

    # Optional, but highly recommended for state locking to prevent conflicts
    # dynamodb_table = "your-terraform-lock-table-name"
  }
} 