# Enterprise Advanced IAM Reporting Automation

This directory contains the highly scalable, fully automated, and enterprise-grade reporting engine for extracting advanced Identity and Access Management (IAM) metrics from Microsoft Entra ID. It stages the high-value data within an Azure Log Analytics Workspace, establishing an extremely robust foundation for advanced Power BI analytics.

This framework was built adhering to strict "Zero Hardcoded Secrets" principles using Azure System-Assigned Managed Identities.

## Architecture

1.  **Extraction Engine (`powershell/IAM-Reporting/Invoke-EntraIAMExtraction.ps1`)**:
    *   Designed to run as an **Azure Automation Runbook**.
    *   Authenticates to Microsoft Graph API securely without stored credentials using its System-Assigned Managed Identity.
    *   Implements fault tolerance including exponential backoff for Microsoft Graph API throttling (HTTP 429).
    *   Retrieves deep IAM metrics:
        *   **App Governance:** Highly privileged Service Principals with expiring credentials.
        *   **PIM Role Drift:** Tracking Global Administrators (Active vs Eligible).
        *   **Identity Protection:** Real-time visibility into high-risk users and Service Principals.
        *   **Conditional Access:** Tracking policy states and exception groups.
        *   **Dormant Accounts:** Identifying enabled users inactive for >90 days.
        *   **Guest User Risk:** Auditing external users.
        *   **App Consent Anomalies:** Detecting highly privileged OAuth scope grants.
        *   **Token Lifetime Policies:** Organization defaults and active policies.
    *   Generates a dynamic **RiskScore** (0-100) per metric to enable intelligent prioritization.
    *   Pushes formatted data securely using the **Modern Azure Monitor Logs Ingestion API** via Data Collection Rules (DCR), authenticating purely via Managed Identity (eliminating legacy Shared Keys).
    *   Handles **Microsoft Graph API Pagination (`@odata.nextLink`)** and robust throttling/backoff, essential for retrieving all data in large enterprise environments.

2.  **Infrastructure as Code (`terraform/modules/azure_iam_reporting/`)**:
    *   Provisions the protected Log Analytics Workspace (`azurerm_management_lock`).
    *   Provisions the Azure Monitor Data Collection Endpoint (DCE) and Data Collection Rule (DCR) with predefined custom schemas and `IngestedAt` transformations.
    *   Provisions the Azure Automation Account.
    *   Configures the Managed Identity and grants it the `Monitoring Data Sender` role securely on the DCR.

## Deployment Steps

### Step 1: Deploy Infrastructure (Terraform)
1.  Navigate to the module directory:
    ```bash
    cd ../../terraform/modules/azure_iam_reporting
    ```
2.  Initialize and apply:
    ```bash
    terraform init
    terraform apply -auto-approve
    ```
3.  **Crucial Next Step (Post-Terraform):**
    The Terraform output will provide the `automation_account_managed_identity_object_id`. You **must** have an Azure AD Global Administrator or Privileged Role Administrator grant this Object ID the following Microsoft Graph API Application permissions (and grant Admin Consent):
    *   `Directory.Read.All`
    *   `AuditLog.Read.All`
    *   `Policy.Read.All`
    *   `RoleManagement.Read.Directory`
    *   `Application.Read.All`

### Step 2: Configure Azure Automation
1.  In the Azure Portal, navigate to the newly created Azure Automation Account.
2.  Under **Shared Resources -> Variables**, create the following string variables using outputs from Terraform:
    *   `DataCollectionEndpointUri`: The `data_collection_endpoint_logs_ingestion_uri` from the Terraform output.
    *   `DataCollectionRuleImmutableId`: The `data_collection_rule_immutable_id` from the Terraform output.
3.  Import the Runbook:
    *   Import `Invoke-EntraIAMExtraction.ps1` as a PowerShell Runbook (version 5.1).
    *   Publish the Runbook.
    *   Link it to a Schedule (e.g., daily or hourly) to begin the automated extraction loop.

## Power BI Integration Guide

This solution utilizes a modern **Data Lakehouse / Log Analytics** approach, far superior to having Power BI directly query Graph API endpoints, circumventing throttling issues entirely.

1.  Open **Power BI Desktop**.
2.  Select **Get Data -> Azure -> Azure Data Explorer (Kusto)**.
3.  Enter your Log Analytics Workspace URL format: `https://ade.loganalytics.io/subscriptions/<subscription-id>/resourcegroups/<resource-group>/providers/microsoft.operationalinsights/workspaces/<workspace-name>`
4.  Choose **DirectQuery** for near real-time dashboards or **Import** for complex modeling.
5.  Use the following KQL queries to surface your advanced IAM insights:

### KQL Dashboards Examples

**1. PIM Drift: Active vs Eligible Global Admins**
```kusto
IAM_PIMRoleDrift_CL
| summarize ActiveCount = countif(AssignmentType_s == "Active"), EligibleCount = countif(AssignmentType_s == "Eligible") by RoleName_s
| render barchart title="Privileged Identity Management: Role Drift"
```

**2. Shadow IT & App Governance: Expiring Service Principal Secrets**
```kusto
IAM_AppGovernance_CL
| where DaysRemaining_d <= 30
| project AppId_s, DisplayName_s, CredentialType_s, ExpirationDate_t, DaysRemaining_d, Status_s
| order by DaysRemaining_d asc
| render table title="Critical: Service Principals with Expiring Credentials"
```

**3. Identity Protection: High Risk Entities**
```kusto
IAM_IdentityProtection_CL
| summarize Count = count() by RiskLevel_s, UserPrincipalName_s
| render piechart title="High Risk User Distribution"
```