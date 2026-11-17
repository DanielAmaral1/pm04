terraform {
  # bucket, key e region sao passados via `-backend-config` no `terraform init`
  # da pipeline (bucket = secrets.TF_STATE_BUCKET, key = pm04/<environment>/terraform.tfstate),
  # porque dependem do parametro "environment" escolhido na execucao.
  # use_lockfile usa o proprio S3 (condicional writes) para lock, sem depender de DynamoDB.
  backend "s3" {
    use_lockfile = true
    encrypt      = true
  }
}
