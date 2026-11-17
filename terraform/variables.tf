variable "aws_region" {
  description = "Regiao AWS de destino"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Ambiente de destino (dev / homolog / prod) - define tags e o prefixo do state"
  type        = string
  default     = "dev"
}

# --- VM1 (app): Caddy + Nginx(React) + API ---

variable "instance_name" {
  description = "Nome da VM da aplicacao (VM1)"
  type        = string
  default     = "pm04-app"
}

variable "instance_type" {
  description = "Tipo da VM da aplicacao (VM1)"
  type        = string
  default     = "t3.micro"
}

# --- VM2 (banco): MongoDB ---

variable "db_instance_name" {
  description = "Nome da VM do banco de dados (VM2)"
  type        = string
  default     = "pm04-db"
}

variable "db_instance_type" {
  description = "Tipo da VM do banco de dados (VM2)"
  type        = string
  default     = "t3.micro"
}

# --- Acesso ---

variable "ssh_public_key" {
  description = "Chave publica SSH (conteudo do secret SSH_PUBLIC_KEY) usada nas duas VMs"
  type        = string
  sensitive   = true
}

# A porta 22 da VM1 para o IP do runner NAO e declarada aqui: e criada e revogada
# via AWS CLI fora do Terraform (authorize/revoke-security-group-ingress), para que
# essa regra temporaria nunca apareca no plan como drift.
