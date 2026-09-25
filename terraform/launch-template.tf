########################################
# launch-template.tf (minimal + SSM/CloudWatch + tags)
########################################

# Latest Ubuntu 22.04 LTS AMI via SSM
data "aws_ssm_parameter" "ubuntu_2204_ami" {
  name = "/aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id"
}

resource "aws_launch_template" "web_lt" {
  name_prefix   = "web-lt-"
  image_id      = data.aws_ssm_parameter.ubuntu_2204_ami.value
  instance_type = "t3.micro"

  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  # Allows EC2 to access AWS services (SSM, CloudWatch)
  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_instance_profile.name
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -eux

    apt-get update -y
    apt-get install -y apache2

    echo "<h1>hi welcome to autoscaling web server</h1>" > /var/www/html/index.html

    systemctl enable apache2
    systemctl start apache2
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "web-server"
    }
  }
}


