terraform {
  backend "s3" {
    bucket         = "vercara-s3-bucket"
    key            = "terraform-state.tf"
    region         = "us-east-1"
    encrypt        = true
  }
}

# ECR Repo
resource "aws_ecr_repository" "my_ecr_repository" {
  name                 = "web-repo"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

}

resource "null_resource" "docker_push" {
  triggers = {
    always_run = "${timestamp()}"
  }
  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = "${path.root}/../dockerpush.sh ${path.root} ${var.aws_account}"
  }
}


resource "aws_iam_role" "ecs_execution_role" {
  name = "ecs_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy_attachment" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "ecr_policy_attachment" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess"
}

# ECS Cluster
resource "aws_ecs_cluster" "web_cluster" {
  name = "web-cluster"
}

# Application Load Balancer
resource "aws_lb" "web_lb" {
  name               = "web-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = [aws_subnet.web_public_subnet.id, aws_subnet.web_private_subnet.id] #[aws_subnet.web_subnet.id]
}

# ECS Task Definition
resource "aws_ecs_task_definition" "web_task" {
  depends_on = [null_resource.docker_push]
  family                   = "web-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  container_definitions = jsonencode([{
    name  = "web-container"
    image = "${aws_ecr_repository.my_ecr_repository.repository_url}:latest"

    portMappings = [{
      containerPort = 80
      hostPort      = 80
    }],
  logConfiguration = {
    logDriver = "awslogs",
    options   = {
      "awslogs-group"         = aws_cloudwatch_log_group.web_task_logs.name
      "awslogs-region"        = "us-east-1",
      "awslogs-stream-prefix" = "ecs",
    },


  }
  }])

}

# ECS Service
resource "aws_ecs_service" "web_service" {

  name            = "web-service"
  cluster         = aws_ecs_cluster.web_cluster.id
  task_definition = aws_ecs_task_definition.web_task.arn
  launch_type     = "FARGATE"
  desired_count = "1"

  network_configuration {
    subnets         = [aws_subnet.web_public_subnet.id, aws_subnet.web_private_subnet.id]
    security_groups = [aws_security_group.web_sg.id]
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.web_tg.arn
    container_name   = "web-container"
    container_port   = 80
  }

  depends_on = [aws_ecs_task_definition.web_task, aws_lb.web_lb, aws_lb_target_group.web_tg]
}

# Load Balancer Target Group
resource "aws_lb_target_group" "web_tg" {
  name        = "web-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.web_vpc.id
  target_type = "ip"
}

# ALB Listener
resource "aws_lb_listener" "web_listener" {
  load_balancer_arn = aws_lb.web_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
  depends_on = [aws_lb.web_lb]
}

# Auto-scaling
resource "aws_appautoscaling_target" "web_scaling_target" {
  max_capacity       = 5
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.web_cluster.name}/${aws_ecs_service.web_service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "web_scaling_policy" {
  name               = "web-scaling-policy"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.web_scaling_target.resource_id
  scalable_dimension = aws_appautoscaling_target.web_scaling_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.web_scaling_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = 50.0
  }
}

#Cloud Watch Metric
resource "aws_cloudwatch_metric_alarm" "ecs_cpu_alarm" {
  alarm_name          = "web-ecs-cpu-alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"
  threshold           = "75"
  alarm_description   = "CPU utilization alarm for ECS service"
  alarm_actions      = [aws_appautoscaling_policy.web_scaling_policy.arn]
  dimensions = {
    ServiceName = aws_ecs_service.web_service.name
  }
}

#cloudwatch log group
resource "aws_cloudwatch_log_group" "web_task_logs" {
  name = "/ecs/web-task-logs"
}