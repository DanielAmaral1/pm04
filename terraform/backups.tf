data "aws_caller_identity" "current" {}

# Bucket para backups do MongoDB (ops.yml / mongodump). Retencao curta via
# lifecycle: o objetivo e recuperacao operacional durante a feira, nao
# arquivamento de longo prazo (reduz custo apos o evento).
resource "aws_s3_bucket" "backups" {
  bucket        = "pm04-mongo-backups-${var.environment}-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "expire-old-backups"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = 14
    }
  }
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket                  = aws_s3_bucket.backups.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
