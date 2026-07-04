output "instance_id" {
  value = aws_instance.api.id
}

output "public_ip" {
  description = "IP dinamico (sem EIP de proposito - EIP parado cobra)"
  value       = aws_instance.api.public_ip
}

output "api_url" {
  value = "http://${aws_instance.api.public_ip}:8000"
}
