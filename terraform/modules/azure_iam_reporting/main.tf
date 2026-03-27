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

resource "azurerm_management_lock" "rg_lock" {
  name       = "lock-${azurerm_resource_group.iam_reporting_rg.name}"
  scope      = azurerm_resource_group.iam_reporting_rg.id
  lock_level = "CanNotDelete"
  notes      = "Enterprise IAM Reporting Resource Group is protected from accidental deletion."
}

# In an enterprise, you'd forward Entra ID native logs to Log Analytics
# data "azurerm_client_config" "current" {}
# resource "azurerm_monitor_diagnostic_setting" "entra_logs" {
#   name                       = "diag-entra-to-law-${var.environment}"
#   target_resource_id         = "/providers/microsoft.aadiam" # Entra ID tenant level
#   log_analytics_workspace_id = azurerm_log_analytics_workspace.iam_reporting_law.id
#
#   enabled_log {
#     category = "SignInLogs"
#   }
#   enabled_log {
#     category = "AuditLogs"
#   }
#   enabled_log {
#     category = "NonInteractiveUserSignInLogs"
#   }
#   enabled_log {
#     category = "ServicePrincipalSignInLogs"
#   }
# }

resource "azurerm_monitor_data_collection_endpoint" "iam_reporting_dce" {
  name                = "dce-iam-reporting-${var.environment}-${var.location_prefix}"
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

resource "azurerm_log_analytics_workspace_table" "idp_sp_table" {
  workspace_id = azurerm_log_analytics_workspace.iam_reporting_law.id
  name         = "IAM_RiskyServicePrincipals_CL"
  plan         = "Analytics"
}

resource "azurerm_log_analytics_workspace_table" "ca_table" {
  workspace_id = azurerm_log_analytics_workspace.iam_reporting_law.id
  name         = "IAM_ConditionalAccess_CL"
  plan         = "Analytics"
}

resource "azurerm_log_analytics_workspace_table" "dormant_table" {
  workspace_id = azurerm_log_analytics_workspace.iam_reporting_law.id
  name         = "IAM_DormantAccounts_CL"
  plan         = "Analytics"
}

resource "azurerm_log_analytics_workspace_table" "guest_table" {
  workspace_id = azurerm_log_analytics_workspace.iam_reporting_law.id
  name         = "IAM_GuestUserRisk_CL"
  plan         = "Analytics"
}

resource "azurerm_log_analytics_workspace_table" "consent_table" {
  workspace_id = azurerm_log_analytics_workspace.iam_reporting_law.id
  name         = "IAM_AppConsentAnomalies_CL"
  plan         = "Analytics"
}

resource "azurerm_log_analytics_workspace_table" "token_table" {
  workspace_id = azurerm_log_analytics_workspace.iam_reporting_law.id
  name         = "IAM_TokenLifetimePolicies_CL"
  plan         = "Analytics"
}

resource "azurerm_monitor_data_collection_rule" "iam_reporting_dcr" {
  name                        = "dcr-iam-reporting-${var.environment}-${var.location_prefix}"
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
    transform_kql = "source | extend IngestedAt = now()"
    output_stream = "Custom-IAM_AppGovernance_CL"
  }

  data_flow {
    streams      = ["Custom-IAM_PIMRoleDrift_CL"]
    destinations = ["law-destination"]
    transform_kql = "source | extend IngestedAt = now()"
    output_stream = "Custom-IAM_PIMRoleDrift_CL"
  }

  data_flow {
    streams      = ["Custom-IAM_IdentityProtection_CL"]
    destinations = ["law-destination"]
    transform_kql = "source | extend IngestedAt = now()"
    output_stream = "Custom-IAM_IdentityProtection_CL"
  }

  data_flow {
    streams      = ["Custom-IAM_RiskyServicePrincipals_CL"]
    destinations = ["law-destination"]
    transform_kql = "source | extend IngestedAt = now()"
    output_stream = "Custom-IAM_RiskyServicePrincipals_CL"
  }

  data_flow {
    streams      = ["Custom-IAM_ConditionalAccess_CL"]
    destinations = ["law-destination"]
    transform_kql = "source | extend IngestedAt = now()"
    output_stream = "Custom-IAM_ConditionalAccess_CL"
  }

  data_flow {
    streams      = ["Custom-IAM_DormantAccounts_CL"]
    destinations = ["law-destination"]
    transform_kql = "source | extend IngestedAt = now()"
    output_stream = "Custom-IAM_DormantAccounts_CL"
  }

  data_flow {
    streams      = ["Custom-IAM_GuestUserRisk_CL"]
    destinations = ["law-destination"]
    transform_kql = "source | extend IngestedAt = now()"
    output_stream = "Custom-IAM_GuestUserRisk_CL"
  }

  data_flow {
    streams      = ["Custom-IAM_AppConsentAnomalies_CL"]
    destinations = ["law-destination"]
    transform_kql = "source | extend IngestedAt = now()"
    output_stream = "Custom-IAM_AppConsentAnomalies_CL"
  }

  data_flow {
    streams      = ["Custom-IAM_TokenLifetimePolicies_CL"]
    destinations = ["law-destination"]
    transform_kql = "source | extend IngestedAt = now()"
    output_stream = "Custom-IAM_TokenLifetimePolicies_CL"
  }

  stream_declaration {
    stream_name = "Custom-IAM_AppGovernance_CL"
    column {
      name = "TimeGenerated"
      type = "datetime"
    }
    column {
      name = "IngestedAt"
      type = "datetime"
    }
    column {
      name = "RiskScore"
      type = "real"
    }
    column {
      name = "RecordId"
      type = "string"
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
      name = "IngestedAt"
      type = "datetime"
    }
    column {
      name = "RiskScore"
      type = "real"
    }
    column {
      name = "RecordId"
      type = "string"
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
    column {
      name = "ScheduleId"
      type = "string"
    }
  }

  stream_declaration {
    stream_name = "Custom-IAM_IdentityProtection_CL"
    column {
      name = "TimeGenerated"
      type = "datetime"
    }
    column {
      name = "IngestedAt"
      type = "datetime"
    }
    column {
      name = "RiskScore"
      type = "real"
    }
    column {
      name = "RecordId"
      type = "string"
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

  stream_declaration {
    stream_name = "Custom-IAM_RiskyServicePrincipals_CL"
    column {
      name = "TimeGenerated"
      type = "datetime"
    }
    column {
      name = "IngestedAt"
      type = "datetime"
    }
    column {
      name = "RiskScore"
      type = "real"
    }
    column {
      name = "RecordId"
      type = "string"
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

  stream_declaration {
    stream_name = "Custom-IAM_ConditionalAccess_CL"
    column {
      name = "TimeGenerated"
      type = "datetime"
    }
    column {
      name = "IngestedAt"
      type = "datetime"
    }
    column {
      name = "RiskScore"
      type = "real"
    }
    column {
      name = "RecordId"
      type = "string"
    }
    column {
      name = "PolicyName"
      type = "string"
    }
    column {
      name = "State"
      type = "string"
    }
    column {
      name = "HasExceptions"
      type = "boolean"
    }
    column {
      name = "CreatedDateTime"
      type = "datetime"
    }
  }

  stream_declaration {
    stream_name = "Custom-IAM_DormantAccounts_CL"
    column {
      name = "TimeGenerated"
      type = "datetime"
    }
    column {
      name = "IngestedAt"
      type = "datetime"
    }
    column {
      name = "RiskScore"
      type = "real"
    }
    column {
      name = "RecordId"
      type = "string"
    }
    column {
      name = "UserPrincipalName"
      type = "string"
    }
    column {
      name = "LastSignInDateTime"
      type = "datetime"
    }
    column {
      name = "DaysInactive"
      type = "int"
    }
  }

  stream_declaration {
    stream_name = "Custom-IAM_GuestUserRisk_CL"
    column {
      name = "TimeGenerated"
      type = "datetime"
    }
    column {
      name = "IngestedAt"
      type = "datetime"
    }
    column {
      name = "RiskScore"
      type = "real"
    }
    column {
      name = "RecordId"
      type = "string"
    }
    column {
      name = "UserPrincipalName"
      type = "string"
    }
    column {
      name = "AccountEnabled"
      type = "boolean"
    }
    column {
      name = "CreatedDateTime"
      type = "datetime"
    }
  }

  stream_declaration {
    stream_name = "Custom-IAM_AppConsentAnomalies_CL"
    column {
      name = "TimeGenerated"
      type = "datetime"
    }
    column {
      name = "IngestedAt"
      type = "datetime"
    }
    column {
      name = "RiskScore"
      type = "real"
    }
    column {
      name = "RecordId"
      type = "string"
    }
    column {
      name = "GrantId"
      type = "string"
    }
    column {
      name = "ClientId"
      type = "string"
    }
    column {
      name = "PrincipalId"
      type = "string"
    }
    column {
      name = "ConsentType"
      type = "string"
    }
    column {
      name = "HighRiskScopes"
      type = "string"
    }
  }

  stream_declaration {
    stream_name = "Custom-IAM_TokenLifetimePolicies_CL"
    column {
      name = "TimeGenerated"
      type = "datetime"
    }
    column {
      name = "IngestedAt"
      type = "datetime"
    }
    column {
      name = "RiskScore"
      type = "real"
    }
    column {
      name = "RecordId"
      type = "string"
    }
    column {
      name = "PolicyId"
      type = "string"
    }
    column {
      name = "DisplayName"
      type = "string"
    }
    column {
      name = "IsOrganizationDefault"
      type = "boolean"
    }
    column {
      name = "Definition"
      type = "string"
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

# Grant the Automation Account's Managed Identity access to publish logs to the DCR via the correct modern role
resource "azurerm_role_assignment" "aa_dcr_data_sender" {
  scope                = azurerm_monitor_data_collection_rule.iam_reporting_dcr.id
  role_definition_name = "Monitoring Data Sender"
  principal_id         = azurerm_automation_account.iam_reporting_aa.identity[0].principal_id
}

# Note: Granting the Managed Identity Microsoft Graph API permissions (Directory.Read.All, AuditLog.Read.All, etc.)
# requires an Azure AD administrator to run an Admin Consent script or configure it via the Azure Portal.
# We output the Object ID of the Managed Identity for this purpose.
