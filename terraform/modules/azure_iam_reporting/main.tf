terraform {
  required_version = ">= 1.0.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "azuread" {}

resource "azurerm_resource_group" "iam_reporting_rg" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_log_analytics_workspace" "iam_reporting_law" {
  name                = var.log_analytics_workspace_name
  location            = azurerm_resource_group.iam_reporting_rg.location
  resource_group_name = azurerm_resource_group.iam_reporting_rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

# ---------------------------------------------------------------------------------------------------------------------
# Modern Azure Monitor Logs Ingestion API (DCR & DCE)
# ---------------------------------------------------------------------------------------------------------------------

resource "azurerm_monitor_data_collection_endpoint" "iam_reporting_dce" {
  name                = "dce-iam-reporting-prod"
  resource_group_name = azurerm_resource_group.iam_reporting_rg.name
  location            = azurerm_resource_group.iam_reporting_rg.location
  tags                = var.tags
}

resource "azurerm_log_analytics_workspace_table" "app_gov_table" {
  workspace_id = azurerm_log_analytics_workspace.iam_reporting_law.id
  name         = "IAM_AppGovernance_CL"
  plan         = "Analytics"
}

resource "azurerm_log_analytics_workspace_table" "pim_drift_table" {
  workspace_id = azurerm_log_analytics_workspace.iam_reporting_law.id
  name         = "IAM_PIMRoleDrift_CL"
  plan         = "Analytics"
}

resource "azurerm_log_analytics_workspace_table" "idp_table" {
  workspace_id = azurerm_log_analytics_workspace.iam_reporting_law.id
  name         = "IAM_IdentityProtection_CL"
  plan         = "Analytics"
}

resource "azurerm_monitor_data_collection_rule" "iam_reporting_dcr" {
  name                        = "dcr-iam-reporting-prod"
  resource_group_name         = azurerm_resource_group.iam_reporting_rg.name
  location                    = azurerm_resource_group.iam_reporting_rg.location
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.iam_reporting_dce.id
  tags                        = var.tags

  destinations {
    log_analytics {
      name                  = "law-destination"
      workspace_resource_id = azurerm_log_analytics_workspace.iam_reporting_law.id
    }
  }

  data_flow {
    streams      = ["Custom-IAM_AppGovernance_CL"]
    destinations = ["law-destination"]
    transform_kql = "source"
    output_stream = "Custom-IAM_AppGovernance_CL"
  }

  data_flow {
    streams      = ["Custom-IAM_PIMRoleDrift_CL"]
    destinations = ["law-destination"]
    transform_kql = "source"
    output_stream = "Custom-IAM_PIMRoleDrift_CL"
  }

  data_flow {
    streams      = ["Custom-IAM_IdentityProtection_CL"]
    destinations = ["law-destination"]
    transform_kql = "source"
    output_stream = "Custom-IAM_IdentityProtection_CL"
  }

  stream_declaration {
    stream_name = "Custom-IAM_AppGovernance_CL"
    column {
      name = "TimeGenerated"
      type = "datetime"
    }
    column {
      name = "AppId"
      type = "string"
    }
    column {
      name = "DisplayName"
      type = "string"
    }
    column {
      name = "CredentialType"
      type = "string"
    }
    column {
      name = "ExpirationDate"
      type = "datetime"
    }
    column {
      name = "DaysRemaining"
      type = "real"
    }
    column {
      name = "Status"
      type = "string"
    }
  }

  stream_declaration {
    stream_name = "Custom-IAM_PIMRoleDrift_CL"
    column {
      name = "TimeGenerated"
      type = "datetime"
    }
    column {
      name = "PrincipalName"
      type = "string"
    }
    column {
      name = "PrincipalId"
      type = "string"
    }
    column {
      name = "RoleName"
      type = "string"
    }
    column {
      name = "AssignmentType"
      type = "string"
    }
    column {
      name = "IsPermanent"
      type = "boolean"
    }
  }

  stream_declaration {
    stream_name = "Custom-IAM_IdentityProtection_CL"
    column {
      name = "TimeGenerated"
      type = "datetime"
    }
    column {
      name = "UserPrincipalName"
      type = "string"
    }
    column {
      name = "RiskLevel"
      type = "string"
    }
    column {
      name = "RiskDetail"
      type = "string"
    }
    column {
      name = "RiskLastUpdatedDateTime"
      type = "datetime"
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# Azure Automation Account
# ---------------------------------------------------------------------------------------------------------------------

resource "azurerm_automation_account" "iam_reporting_aa" {
  name                = var.automation_account_name
  location            = azurerm_resource_group.iam_reporting_rg.location
  resource_group_name = azurerm_resource_group.iam_reporting_rg.name
  sku_name            = "Basic"

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

# Grant the Automation Account's Managed Identity access to publish metrics/logs to the DCR
resource "azurerm_role_assignment" "aa_dcr_publisher" {
  scope                = azurerm_monitor_data_collection_rule.iam_reporting_dcr.id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = azurerm_automation_account.iam_reporting_aa.identity[0].principal_id
}

# Note: Granting the Managed Identity Microsoft Graph API permissions (Directory.Read.All, AuditLog.Read.All, etc.)
# requires an Azure AD administrator to run an Admin Consent script or configure it via the Azure Portal.
# We output the Object ID of the Managed Identity for this purpose.
