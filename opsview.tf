data "aws_vpcs" "vpc" {}

provider "aws" {
  region = "eu-west-2"
}

resource "aws_security_group" "opsview-sg" {
  name        = "opsview-sg"
  description = "SG for Opsview HTTP/SSH"
  vpc_id      = "${element(data.aws_vpcs.vpc.ids,0)}"

  tags = {
    Name = "opsview-sg"
  }

  ingress {
    cidr_blocks = ["96.237.247.97/32"]
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    description = "allow SSH from self"
  }

  ingress {
    cidr_blocks = ["96.237.247.97/32"]
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    description = "allow MySQL connection"
  }

  ingress {
    cidr_blocks = ["96.237.247.97/32"]
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    description = "allow HTTP from self"
  }

  ingress {
    cidr_blocks = ["96.237.247.97/32"]
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    description = "allow https from self"
  }

  ingress {
    self        = true
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    description = "allow MySQL connection on 3306 from within sg"
  }

  revoke_rules_on_delete = true
}

resource "aws_db_parameter_group" "opsviewdb_params" {
  name        = "opsviewdb-param"
  family      = "mysql5.7"
  description = "Parameter group for Opsview database"

  parameter {
    name  = "innodb_file_per_table"
    value = 1
  }

  parameter {
    name  = "innodb_flush_log_at_trx_commit"
    value = 2
  }

  tags = {
    key   = "Name"
    value = "opsview"
  }
}

resource "aws_db_instance" "opsviewdb" {
  allocated_storage           = 20
  allow_major_version_upgrade = false
  apply_immediately           = true
  backup_retention_period     = 0
  engine                      = "mysql"
  engine_version              = "5.7"
  identifier                  = "opsview-v6"
  instance_class              = "db.t2.medium"
  parameter_group_name        = "${aws_db_parameter_group.opsviewdb_params.name}"
  password                    = "${var.password}"
  username                    = "admin"
  vpc_security_group_ids      = ["${aws_security_group.opsview-sg.id}"]
  publicly_accessible         = true
  skip_final_snapshot         = true
  depends_on                  = ["aws_db_parameter_group.opsviewdb_params"]
}

resource "aws_key_pair" "opsview-kp" {
  key_name   = "opsview-kp"
  public_key = "${file("/home/mkhalid/.ssh/id_rsa.pub")}"
}

resource "aws_instance" "opsview_orch" {
  ami                                  = "ami-7c1bfd1b"
  instance_initiated_shutdown_behavior = "terminate"
  instance_type                        = "t2.large"
  vpc_security_group_ids               = ["${aws_security_group.opsview-sg.id}"]
  associate_public_ip_address          = true
  key_name                             = "${aws_key_pair.opsview-kp.key_name}"

  tags = {
    Name = "opsview-orchestrator"
  }
}

output "db_instance" {
  value = "${aws_db_instance.opsviewdb.endpoint}"
}

output "ec2_instance" {
  value = "${aws_instance.opsview_orch.public_dns}"
}
