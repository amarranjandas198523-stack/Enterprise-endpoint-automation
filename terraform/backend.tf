# backend.tf
# Enterprise remote state configuration for Terraform

terraform {
  # Example S3 backend configuration.
  # For production, ensure state locking (e.g., via DynamoDB) is enabled.
  # Replace values with your actual enterprise bucket, key, region, etc.

  # backend "s3" {
  #   bucket         = "my-enterprise-terraform-state-bucket"
  #   key            = "endpoint-management/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-lock"
  # }

  # Example Azure RM backend configuration
  # backend "azurerm" {
  #   resource_group_name  = "rg-terraform-state"
  #   storage_account_name = "stterraformstate"
  #   container_name       = "tfstate"
  #   key                  = "endpoint-management.tfstate"
  # }
}
