data "aws_vpcs" "myvpc" {}

provider "aws" {
  region = "us-east-1"
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

  user_data = <<-EOF
#!/bin/bash
sudo yum -y install mlocate
sudo updatedb
sudo aws --region us-east-1 s3 cp <bucket-name>/<object-name> .
-EOF

  security_groups      = ["${data.aws_security_groups.my_sg.ids}"]
  key_name             = "${aws_key_pair.my_key.key_name}"
  iam_instance_profile = "${aws_iam_instance_profile.instance_profile.name}"

  lifecycle {
    create_before_destroy = false
  }
}

resource "aws_autoscaling_group" "amazon-asg" {
  name                 = "terraform-asg"
  max_size             = 2
  min_size             = 1
  default_cooldown     = 300
  launch_configuration = "${aws_launch_configuration.amazonami.name}"
  health_check_type    = "EC2"
  desired_capacity     = 1

  tag = [{
    key                 = "Name"
    value               = "Terraform-Deployment"
    propagate_at_launch = true
  }]

  vpc_zone_identifier = ["${data.aws_subnet_ids.mysubnets.ids}"]
}

data "aws_instances" "myinstances" {
  instance_tags = {
    Name = "Terraform-Deployment"
  }
}

output "ip_addr" {
  value = "${data.aws_instances.myinstances.public_ips}"
}
