# Espelho da stack 02-compute.yaml, recurso a recurso.

# Equivalente do parametro AWS::SSM::Parameter::Value<AWS::EC2::Image::Id>:
# no Terraform a resolucao e um data source lido a cada plan (fonte de drift
# controlado - a AMI "current" muda com o tempo).
data "aws_ssm_parameter" "ubuntu_2204_ami" {
  name = "/aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_iam_role" "instance" {
  name_prefix = "coffee-shop-instance-"
  description = "coffee-shop EC2 - SSM core + artefatos CodeDeploy + parametros da app"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "artifacts_read" {
  name = "coffee-shop-artifacts-read"
  role = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "ReadDeployArtifacts"
      Effect = "Allow"
      Action = ["s3:GetObject", "s3:GetObjectVersion", "s3:ListBucket"]
      Resource = [
        "arn:aws:s3:::coffee-shop-artifacts-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}",
        "arn:aws:s3:::coffee-shop-artifacts-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}/*",
      ]
    }]
  })
}

resource "aws_iam_role_policy" "parameters_read" {
  name = "coffee-shop-parameters-read"
  role = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "ReadAppParameters"
      Effect   = "Allow"
      Action   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
      Resource = "arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter/coffee-shop/*"
    }]
  })
}

resource "aws_iam_instance_profile" "instance" {
  name_prefix = "coffee-shop-instance-"
  role        = aws_iam_role.instance.name
}

resource "aws_instance" "api" {
  ami                    = data.aws_ssm_parameter.ubuntu_2204_ami.value
  instance_type          = var.instance_type
  key_name               = var.key_name != "" ? var.key_name : null
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.instance.name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    delete_on_termination = true
  }

  user_data = <<-EOF
    #!/bin/bash -xe
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y ruby-full wget python3-venv python3-pip

    id -u coffee &>/dev/null || useradd --system --create-home --shell /usr/sbin/nologin coffee
    mkdir -p /opt/coffee-shop /etc/coffee-shop
    chown coffee:coffee /opt/coffee-shop

    cd /tmp
    wget -q https://aws-codedeploy-${data.aws_region.current.region}.s3.${data.aws_region.current.region}.amazonaws.com/latest/install
    chmod +x ./install
    ./install auto
    systemctl enable --now codedeploy-agent
  EOF

  tags = {
    Name = "coffee-shop-api-iaas"
    Role = "api-iaas"
  }
}
