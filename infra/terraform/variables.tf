variable "vpc_cidr" {
  description = "CIDR da VPC (mesmo valor da stack 01-network)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR da subnet publica"
  type        = string
  default     = "10.0.1.0/24"
}

variable "instance_type" {
  description = "Tipo da instancia da coffee-api (t3.micro basta)"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "Key pair OPCIONAL (vazio = sem chave; acesso via Session Manager)"
  type        = string
  default     = ""
}
