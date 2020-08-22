terraform {
  required_version = ">= 0.12"
}

provider "aws" {
  version = ">= 3.0"
  region  = var.region
}
