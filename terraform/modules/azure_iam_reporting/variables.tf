variable "resource_group_name" {
  description = "The name of the resource group where the IAM reporting infrastructure will be created."
  type        = string
  default     = "rg-iam-reporting-prod"
}

variable "location" {
  description = "The Azure region where the IAM reporting infrastructure will be created."
  type        = string
  default     = "eastus"
}

variable "location_prefix" {
  description = "Short name for the region used in naming conventions (e.g. eus, wus2)."
  type        = string
  default     = "eus"
}

variable "environment" {
  description = "The environment tier (e.g., prod, dev, staging)."
  type        = string
  default     = "prod"
}

variable "log_analytics_workspace_name" {
  description = "The name of the Log Analytics Workspace for IAM reporting."
  type        = string
  default     = "law-iam-reporting-prod"
}

variable "automation_account_name" {
  description = "The name of the Azure Automation Account."
  type        = string
  default     = "aa-iam-reporting-prod"
}

variable "tags" {
  description = "Tags to apply to the resources."
  type        = map(string)
  default = {
    Environment = "Production"
    Project     = "IAM-Reporting-Automation"
    Owner       = "Identity-Security-Team"
  }
}
