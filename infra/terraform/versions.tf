# Espelho Terraform das stacks 01-network + 02-compute (material do bloco de
# comparacao CloudFormation x Terraform - docs/COMPARACAO_CFN_TERRAFORM.md).
# Mesmos valores, mesma topologia; apply e OPCIONAL e nunca deve coexistir
# com as stacks CloudFormation (recursos duplicados = custo duplicado).

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # Equivalente Terraform das --tags aplicadas as stacks CloudFormation:
  # aqui a propagacao e feita pelo provider, la pelo servico de stacks.
  default_tags {
    tags = {
      Project = "coffee-shop"
      Team    = "grupo8"
      Env     = "demo"
    }
  }
}
