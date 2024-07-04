data "external" "env" {
  program = ["./avn-token.sh"]
}

data "env_variable" "access_key" {
  name = "AWS_ACCESS_KEY"
}

data "env_variable" "secret_key" {
  name = "AWS_SECRET_ACCESS_KEY"
}

locals {
  aws_access_key        = coalesce(data.env_variable.access_key.value, var.aws_access_key)
  aws_secret_access_key = coalesce(data.env_variable.secret_key.value, var.aws_secret_access_key)
}
