# SG da VM1 (app): 80/443 publicos. A porta 22 para o IP do runner
# e aberta/revogada via AWS CLI fora do Terraform (ver README) para nao gerar drift.
resource "aws_security_group" "app" {
  name        = "pm04-sg-app"
  description = "VM1 - Caddy/Nginx/API: HTTP/HTTPS publicos"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP publico (redirecionado para HTTPS pelo Caddy)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS publico"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "pm04-sg-app"
  }
}

# SG da VM2 (banco): nenhuma porta publica. 27017 e 22 liberados apenas
# a partir do SG da VM1 (acesso Ansible via ProxyJump pela VM1).
resource "aws_security_group" "db" {
  name        = "pm04-sg-db"
  description = "VM2 - MongoDB: acesso somente a partir da VM1"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MongoDB somente a partir da VM1 (API)"
    from_port       = 27017
    to_port         = 27017
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  ingress {
    description     = "SSH somente a partir da VM1 (ProxyJump do Ansible)"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "pm04-sg-db"
  }
}
