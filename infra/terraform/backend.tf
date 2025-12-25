# terraform {
#   backend "s3" {
#     bucket         = "hypernova-state-bucket"
#     key            = "state/terraform.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "terraform-lock"
#   }
# }