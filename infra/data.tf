data "aws_availability_zones" "available" {}

data "aws_iam_policy_document" "ecs_task_execution_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}