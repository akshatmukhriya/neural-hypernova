terraform {
  backend "s3" {
    # We will leave these as placeholders or common names. 
    # The Jockey will override these during 'init' to ensure success.
    bucket         = "hypernova-state-placeholder" 
    key            = "eks/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
  }
}