# Microsoft Purview DLP to ServiceNow Automation

This directory contains the automation scripts for deploying an Enterprise-grade Data Loss Prevention (DLP) framework within Microsoft Purview (Microsoft 365) and automatically synchronizing DLP alerts to ServiceNow Incidents.

## Overview

The solution consists of two primary PowerShell scripts:

1. **`Deploy-PurviewDLP.ps1`**: Deploys comprehensive DLP policies across Exchange, SharePoint, OneDrive, and Endpoints covering PII, Financial Data, Health (HIPAA), and GDPR. It enforces strict blocking for high-severity issues while allowing business justification overrides for low-to-medium severity issues.
2. **`Sync-DLPAlertsToServiceNow.ps1`**: Connects to the Microsoft Graph API, retrieves Purview DLP alerts generated within a specified timeframe, and pushes these alerts as Incidents into ServiceNow via the ServiceNow REST API.

## Directory Structure

```text
Purview-DLP-Automation/
├── Scripts/
│   ├── Deploy-PurviewDLP.ps1
│   └── Sync-DLPAlertsToServiceNow.ps1
├── Config/
│   └── Config.json (Placeholder for configuration files)
└── Docs/
    └── README.md
```

## Prerequisites

### For Deployment (`Deploy-PurviewDLP.ps1`)

* The script requires the **ExchangeOnlineManagement** PowerShell module. You can install it via:
  ```powershell
  Install-Module ExchangeOnlineManagement -Force
  ```
* You must have sufficient permissions to connect to the Security & Compliance Center (e.g., Compliance Administrator or Global Administrator).
* Ensure you authenticate using `Connect-IPPSSession` before running or configure App-Only authentication for full automation.
* A designated shared mailbox (e.g., `dlp-alerts@yourdomain.com`) must exist to receive incident reports (this maintains a copy of the blocked data as evidence).

### For ServiceNow Sync (`Sync-DLPAlertsToServiceNow.ps1`)

* **Azure AD App Registration**: Create an App Registration with `SecurityEvents.Read.All` or `SecurityAlert.Read.All` Graph API permissions (Application permissions) and generate a Client Secret.
* **ServiceNow Account**: Create an integration user account in ServiceNow with roles capable of creating incidents (e.g., `itil` or a custom REST API role).
* **Environment Variables / Key Vault**: In a production environment, store the following securely as environment variables or retrieve them from an Azure Key Vault:
  * `TENANT_ID`
  * `CLIENT_ID`
  * `CLIENT_SECRET`
  * `SERVICENOW_INSTANCE` (e.g., `dev12345`)
  * `SERVICENOW_USER`
  * `SERVICENOW_PASSWORD`

## Usage

### 1. Deploy DLP Policies

Open a PowerShell session as Administrator, navigate to `Purview-DLP-Automation/Scripts/`, and execute:

```powershell
# Deploy with default parameters (will prompt for IPPS Session login if not connected)
.\Deploy-PurviewDLP.ps1 -IncidentReportMailbox "dlp-evidence@yourcompany.com"
```

*Note: Microsoft 365 DLP policy propagation can take up to 24 hours to fully enforce across all workloads.*

### 2. Synchronize Alerts to ServiceNow

This script is designed to run as a scheduled task, Azure Automation Runbook, or Azure Function every hour (or your preferred cadence).

```powershell
# The script pulls variables from the environment ($env:TENANT_ID, etc.)
# Run the sync for alerts generated in the past 1 hour:
.\Sync-DLPAlertsToServiceNow.ps1 -HoursToQuery 1
```

## Exception Management & Incident Reports

* **High Severity**: Blocks sensitive data sharing (e.g., >= 10 credit cards) entirely with no override option.
* **Low/Medium Severity**: Blocks sharing but allows users to click an "Override" button if they provide a valid business justification.
* **Evidence Retention**: Both scenarios automatically generate a full incident report (including the matched content and surrounding text) and send it to the designated DLP shared mailbox, ensuring compliance teams have the necessary evidence for auditing.
