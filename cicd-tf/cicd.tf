variable "account_id" {
  description = "Enter AWS Account ID"
}
#s3 Bucket
resource "aws_s3_bucket" "artifact_bucket" {
  bucket = "vercara-s3-bucket"
}

resource "aws_s3_bucket_versioning" "versioning_example" {
  bucket = aws_s3_bucket.artifact_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

#Code build IAM Role & Policy
resource "aws_iam_role" "codebuild_role" {
  name = "web-codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
      }
    ]
  })

  inline_policy {
    name = "codebuild-policy"
    policy = jsonencode({
      Version = "2012-10-17",
      Statement = [
        {
          "Effect" : "Allow",
          "Action" : [
            "ecs:*",
            "ecr:*",
            "ec2:*",
            "iam:*",
            "logs:*",
            "s3:*",
            "elasticloadbalancing:*",
            "cloudwatch:*",
            "application-autoscaling:*"
          ],
          "Resource" : "*"
        }
      ]
    })
  }
}


# Code Build Project

resource "aws_codebuild_project" "terraform_build" {
  name          = "web-codebuild-project"
  description   = "Terraform CodeBuild Project"
  service_role  = aws_iam_role.codebuild_role.arn
  build_timeout = "30"

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec.yml"
  }

  artifacts {
    type           = "CODEPIPELINE"
    namespace_type = "BUILD_ID"
    packaging      = "ZIP"
  }
  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:4.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true

    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = var.account_id
    }
  }

}

resource "aws_iam_role_policy_attachment" "cloudwatch_permission" {
  role       = aws_iam_role.pipeline_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccess"
}
#Code Pipeline IAM Role & Policy
resource "aws_iam_role" "pipeline_role" {
  name = "web-codepipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "codepipeline.amazonaws.com"
        }
      }
    ]
  })

  inline_policy {
    name = "codepipeline-policy"
    policy = jsonencode({
      Version = "2012-10-17",
      Statement = [
        {
          Action   = "codepipeline:*",
          Effect   = "Allow",
          Resource = "*"
        }
      ]
    })
  }
}

resource "aws_iam_role_policy_attachment" "codestar_permission" {
  role       = aws_iam_role.pipeline_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeStarServiceRole"
}

resource "aws_iam_role_policy_attachment" "s3_permission" {
  role       = aws_iam_role.pipeline_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}
# Code pipeline
resource "aws_codepipeline" "terraform_pipeline" {
  name     = "web-codepipeline"
  role_arn = aws_iam_role.pipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.artifact_bucket.id
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.web-connection.arn
        FullRepositoryId = "dche25/vercara_project",
        BranchName       = "master",

      }
    }
  }

  stage {
    name = "Build"

    action {
      name            = "BuildAction"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["source_output"]
      version         = "1"

      configuration = {
        ProjectName = aws_codebuild_project.terraform_build.name
      }
    }
  }
}

resource "aws_codestarconnections_connection" "web-connection" {
  name          = "web-connection"
  provider_type = "GitHub"
}


