output "resource_group_name" {
  description = "The name of the Resource Group created."
  value       = azurerm_resource_group.iam_reporting_rg.name
}

output "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics Workspace."
  value       = azurerm_log_analytics_workspace.iam_reporting_law.workspace_id
}

output "data_collection_endpoint_logs_ingestion_uri" {
  description = "The Logs Ingestion URI of the Data Collection Endpoint."
  value       = azurerm_monitor_data_collection_endpoint.iam_reporting_dce.logs_ingestion_endpoint
}

output "data_collection_rule_immutable_id" {
  description = "The Immutable ID of the Data Collection Rule (required for ingestion)."
  value       = azurerm_monitor_data_collection_rule.iam_reporting_dcr.immutable_id
}

output "automation_account_name" {
  description = "The name of the Automation Account."
  value       = azurerm_automation_account.iam_reporting_aa.name
}

output "automation_account_managed_identity_object_id" {
  description = "The Object ID of the System-Assigned Managed Identity attached to the Automation Account. You must grant this identity Microsoft Graph API permissions."
  value       = azurerm_automation_account.iam_reporting_aa.identity[0].principal_id
}
