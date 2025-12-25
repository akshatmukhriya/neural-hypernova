terraform {
  backend "s3" {
    bucket = "hypernova-state-bucket"
    key    = "eks/terraform.tfstate"
    region = "us-east-1"
  }
}