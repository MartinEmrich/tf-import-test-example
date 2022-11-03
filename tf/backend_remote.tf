terraform {
  required_version = ">= 1.1.0"
  backend "s3" {
    bucket                  = "tf-import-test-terraform"
    key                     = "terraform_state"
    encrypt                 = true
  }
}
