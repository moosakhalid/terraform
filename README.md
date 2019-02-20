# terraform
My terraform templates

Plug in relevant SSH public_keys and bucket names into asg.tf terraform aws template when using it

Added new resources and functionality. Template now creates ASG behind an target group and ALB. Attaches the LB public DNS to R53 hosted zone and updates the NS of registered zone.

Some variables that'll need to be supplied by user: 

ssh public key i.e. if you associate public IP with ASG instances in launch configuration.

Valid bucket names

Valid Security group tag do fetch the right security group ID and you can give it necessary rights to access things on ASG spun up EC2 instances.

Your AWS registered domain. In the aws_route53_zone resource it is assumed that always 4 NS are returned which are than used in provisioner local-exec command to update the AWS registered domain name since right now Terraform does not offer the functionality to do that through a resource for which a feature request is open here : https://github.com/terraform-providers/terraform-provider-aws/issues/88

Another issue when creating RDS instance without specifying "skip_final_snapshot" to true.
https://github.com/hashicorp/terraform/issues/5417
On destroy you'll get an error saying no snapshot identifier given as by default "skip_final_snapshot" is false and therefore a snapshot is expected on deletion. The workaround was to manually modify the terraform.tfstate file and change "skip_final_snapshot" from false to true and run terraform destroy again.
