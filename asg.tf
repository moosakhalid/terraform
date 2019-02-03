data "aws_vpcs" "myvpc" {}

provider "aws" {
  region = "us-east-1"
}

resource "aws_route53_zone" "primary" {
  name    = "<your-registered-domain"
  comment = "terraform generated"

  tags = {
    Name = "terraform-deployment"
  }

  provisioner "local-exec" {
    command = "aws --region us-east-1 route53domains update-domain-nameservers --domain-name thelinuxdreamer.com --output text --nameservers Name=${element(aws_route53_zone.primary.name_servers,0)} Name=${element(aws_route53_zone.primary.name_servers,1)} Name=${element(aws_route53_zone.primary.name_servers,2)} Name=${element(aws_route53_zone.primary.name_servers,3)}"
  }

  depends_on = ["aws_alb.alb"]
  depends_on = ["aws_autoscaling_group.amazon-asg"]
}

resource "aws_route53_record" "hosted_zones" {
  zone_id = "${aws_route53_zone.primary.zone_id}"
  name    = "tf.thelinuxdreamer.com"
  type    = "A"

  alias = {
    name                   = "${aws_alb.alb.dns_name}"
    zone_id                = "${aws_alb.alb.zone_id}"
    evaluate_target_health = true
  }

  depends_on = ["aws_alb.alb"]
}

resource "aws_alb" "alb" {
  name               = "application-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = ["${data.aws_security_groups.my_sg.ids}"]
  subnets            = ["${data.aws_subnet_ids.mysubnets.ids}"]

  tags = {
    key   = "name"
    value = "terraform-generated-alb"
  }
}

resource "aws_lb_target_group" "terraform-alb" {
  name        = "terraform-alb"
  target_type = "instance"
  port        = "80"
  vpc_id      = "${element(data.aws_vpcs.myvpc.ids,0)}"
  protocol    = "HTTP"

  health_check = {
    path     = "/"
    interval = "30"
    port     = "80"
    protocol = "HTTP"
    matcher  = "200-299"
  }

  tags = {
    name = "terraform-alb"
  }
}

resource "aws_lb_listener" "alb_listener" {
  load_balancer_arn = "${aws_alb.alb.arn}"
  port              = "80"
  protocol          = "HTTP"

  default_action = {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.terraform-alb.arn}"
  }
}

resource "aws_iam_role" "s3_role" {
  name = "role"

  assume_role_policy = <<EOF
{
      "Version": "2012-10-17",
      "Statement": [
        {
          "Action": "sts:AssumeRole",
          "Principal": {
            "Service": "ec2.amazonaws.com"
          },
          "Effect": "Allow"
        }
      ]
    }
EOF
}

resource "aws_iam_role_policy" "policy" {
  name = "s3-policy"
  role = "${aws_iam_role.s3_role.id}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:ListBucket"
      ],
      "Effect": "Allow",
      "Resource": "arn:aws:s3:::<bucket-name>"
    },
{
      "Action": [
        "s3:GetObject"
      ],
      "Effect": "Allow",
      "Resource": "arn:aws:s3:::<bucket-name>/*"
    }

  ]
}
EOF
}

resource "aws_iam_instance_profile" "instance_profile" {
  name = "terraform-generated"
  role = "${aws_iam_role.s3_role.name}"
}

resource "aws_key_pair" "my_key" {
  key_name   = "terraform-deploy-key"
  public_key = "<ssh-rsa .....AAAAB3NzaC1yc2EAAAADAQABAAABAQCjAwOwL........>"
}

data "aws_security_groups" "my_sg" {
  tags = {
    Name = "<My-Security-Group-Name-tag>"
  }
}

data "aws_subnet_ids" "mysubnets" {
  vpc_id = "${element(data.aws_vpcs.myvpc.ids,0)}"
}

output "subnets" {
  value = "${data.aws_subnet_ids.mysubnets.ids}"
}

resource "aws_launch_configuration" "amazonami" {
  name                        = "terraform-launch-config"
  image_id                    = "ami-035be7bafff33b6b6"
  instance_type               = "t2.micro"
  associate_public_ip_address = true

  user_data = <<EOF
#!/bin/bash

sudo iptables -F
sudo setenforce 0
sudo yum -y install httpd
sudo systemctl start httpd
sudo yum -y install mlocate
sudo updatedb
sudo aws --region us-east-1 s3 cp s3://<bucket-name>/<object-name> .
EOF

  security_groups      = ["${data.aws_security_groups.my_sg.ids}"]
  key_name             = "${aws_key_pair.my_key.key_name}"
  iam_instance_profile = "${aws_iam_instance_profile.instance_profile.name}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "amazon-asg" {
  name                 = "terraform-asg"
  max_size             = 2
  min_size             = 1
  default_cooldown     = 300
  launch_configuration = "${aws_launch_configuration.amazonami.name}"
  health_check_type    = "ELB"
  desired_capacity     = 2

  tag = [{
    key                 = "Name"
    value               = "Terraform-Deployment"
    propagate_at_launch = true
  }]

  vpc_zone_identifier = ["${data.aws_subnet_ids.mysubnets.ids}"]
  target_group_arns   = ["${aws_lb_target_group.terraform-alb.arn}"]
  depends_on          = ["aws_iam_role_policy.policy"]
}

data "aws_instances" "myinstances" {
  instance_tags = {
    Name = "Terraform-Deployment"
  }

  depends_on = ["aws_autoscaling_group.amazon-asg"]
}

output "ip_addr" {
  value = "${data.aws_instances.myinstances.public_ips}"
}

output "alb" {
  value = "${aws_alb.alb.dns_name}"
}

output "dns_name" {
  value = "${aws_route53_zone.primary.name}"
}
