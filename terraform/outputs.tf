output "app_public_ip" {
  description = "Elastic IP da VM1 (app) - usado tambem no dominio sslip.io"
  value       = aws_eip.app.public_ip
}

output "app_instance_id" {
  value = aws_instance.app.id
}

output "db_public_ip" {
  description = "IP publico da VM2 (somente para saida - apt/docker); nao usado para entrada"
  value       = aws_instance.db.public_ip
}

output "db_private_ip" {
  description = "IP privado da VM2 - usado pela API para conectar ao MongoDB"
  value       = aws_instance.db.private_ip
}

output "db_instance_id" {
  value = aws_instance.db.id
}

output "sg_app_id" {
  value = aws_security_group.app.id
}

output "sg_db_id" {
  value = aws_security_group.db.id
}
