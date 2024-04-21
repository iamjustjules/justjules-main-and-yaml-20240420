resource "aws_instance" "example" {
  ami           = data.aws_ami.example.id
  instance_type = "t2.micro"

  tags = {
    Name = "ExampleInstance"
  }
}

# Create an AMI that will start a machine whose root device is backed by
# an EBS volume populated from a snapshot. We assume that such a snapshot
# already exists with the id "snap-xxxxxxxx".
/*
resource "aws_ami" "example" {
  name                = "terraform-example"
  virtualization_type = "hvm"
  root_device_name    = "/dev/sda1"
  imds_support        = "v2.0" # Enforce usage of IMDSv2. You can safely remove this line if your application explicitly doesn't support it.
  
  ebs_block_device {
    device_name = "/dev/sda1"
    snapshot_id = "snap-08bdb8bad3d038d45"
    volume_size = 100
    volume_type = "gp2"
    delete_on_termination = true
  }
  
}


resource "aws_ami_from_instance" "example" {
  name               = "terraform-example"
  source_instance_id = "i-0f5ea46cf6f68eb1d"
}
*/

# Data source to get the AMI ID based on certain filters
data "aws_ami" "example" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"] # Adjust the AMI name pattern to match your needs
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  owners = ["amazon"] #from the snapshots under EBS: https://us-east-1.console.aws.amazon.com/ec2/home?region=us-east-1#Snapshots:

}

resource "aws_launch_configuration" "example" {
  name            = "web_config"
  image_id        = data.aws_ami.example.id
  instance_type   = "t2.micro"
  security_groups = [aws_security_group.example.id]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "example" {
  name        = "example"
  description = "Allow TLS inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.example.id

  tags = {
    Name = "example"
  }
}

resource "aws_vpc_security_group_ingress_rule" "example_ipv4" {
  security_group_id = aws_security_group.example.id
  cidr_ipv4         = aws_vpc.example.cidr_block
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.example.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

/*
resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv6" {
  security_group_id = aws_security_group.example.id
  cidr_ipv6         = "::/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}
*/

resource "aws_vpc" "example" {
  cidr_block           = "10.0.0.0/16" #[aws_subnet.example1.id,aws_subnet.example2.id]
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "example"
  }
}

resource "aws_internet_gateway" "example" {
  vpc_id = aws_vpc.example.id

  tags = {
    Name = "example"
  }
}

resource "aws_subnet" "example1" {
  vpc_id            = aws_vpc.example.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "example1"
  }
}

resource "aws_subnet" "example2" {
  vpc_id            = aws_vpc.example.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "example2"
  }
}

resource "aws_subnet" "example3" {
  vpc_id            = aws_vpc.example.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1c"

  tags = {
    Name = "example3"
  }
}

resource "aws_autoscaling_group" "example" {
  launch_configuration = aws_launch_configuration.example.id
  min_size             = 1
  max_size             = 10
  desired_capacity     = 1
  vpc_zone_identifier  = [aws_subnet.example1.id, aws_subnet.example2.id, aws_subnet.example3.id]

  tag {
    key                 = "Name"
    value               = "terraform-asg-example"
    propagate_at_launch = true
  }
}

resource "aws_lb" "example" {
  name               = "terraform-asg-example"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.example.id]
  subnets            = [aws_subnet.example1.id, aws_subnet.example2.id, aws_subnet.example3.id]

  tags = {
    name = "exampleLoadBalancer"
  }
}

resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "High CPU Utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 75
  alarm_description   = "This metric monitors ec2 cpu utilization"
  actions_enabled     = true

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.example.name
  }

  alarm_actions             = [aws_sns_topic.topic_alarm.arn]
  ok_actions                = [aws_sns_topic.topic_alarm.arn]
  insufficient_data_actions = [aws_sns_topic.topic_alarm.arn]
}

resource "aws_sns_topic" "topic_alarm" {
  name = "asg-high-cpu-topic"
}

resource "aws_dynamodb_table" "my_app_data" {
  name         = "MyApplicationData"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Name = "MyDynamoDBTable"
  }
}

module "dynamodb_table" {
  source = "./modules/dynamodb_table"
}

module "cloudwatch_alarm" {
  source = "./modules/cloudwatch_alarm"
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.my_app_data.name
  description = "The name of the DynamoDB table."
}

output "cloudwatch_alarm_arn" {
  value       = aws_cloudwatch_metric_alarm.high_cpu.arn
  description = "The ARN of the CloudWatch Alarm."
}

output "instance_public_ip" {
  value       = aws_instance.example.public_ip
  description = "The public IP address of the instance."
}

output "ami_used" {
  value       = data.aws_ami.example
  description = "The AMI ID used for the instance."
}
