data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "pm04" {
  key_name   = "pm04-${var.environment}"
  public_key = var.ssh_public_key
}

# VM1 - aplicacao (Caddy + Nginx + API)
resource "aws_instance" "app" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.app.id]
  key_name               = aws_key_pair.pm04.key_name

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
  }

  tags = {
    Name = var.instance_name
    Role = "app"
  }

  lifecycle {
    ignore_changes = [ami]
  }
}

resource "aws_eip" "app" {
  instance = aws_instance.app.id
  domain   = "vpc"

  tags = {
    Name = "${var.instance_name}-eip"
  }
}

# VM2 - banco de dados (MongoDB)
resource "aws_instance" "db" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.db_instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.db.id]
  key_name               = aws_key_pair.pm04.key_name

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
  }

  tags = {
    Name = var.db_instance_name
    Role = "db"
  }

  lifecycle {
    ignore_changes = [ami]
  }
}
