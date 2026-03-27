# ==============================================================================================
# Script Name: Sync-DLPAlertsToServiceNow.ps1
# Description: This script queries the Microsoft 365 Management Activity API (or Graph API) for
#              DLP rule match alerts and creates Incidents in ServiceNow.
#
# Prerequisites:
#   - Azure AD App Registration with 'SecurityEvents.Read.All' or relevant Graph API permissions.
#   - ServiceNow REST API access credentials or Service Account.
#   - Values stored in 'Purview-DLP-Automation/Config/Config.json' or key vault.
# ==============================================================================================

[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = "..\Config\Config.json",

    [Parameter(Mandatory=$false)]
    [int]$HoursToQuery = 1
)

# Function to write timestamped logs
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$Timestamp] [$Level] $Message"
}

# 1. Load Configuration (Simulated for Script)
# In production, these should be retrieved from a secure Key Vault.
$Config = @{
    TenantId = $env:TENANT_ID
    ClientId = $env:CLIENT_ID
    ClientSecret = $env:CLIENT_SECRET
    ServiceNowInstance = $env:SERVICENOW_INSTANCE
    ServiceNowUser = $env:SERVICENOW_USER
    ServiceNowPassword = $env:SERVICENOW_PASSWORD
}

# Ensure required environment variables are set (basic validation)
if (-not $Config.TenantId -or -not $Config.ServiceNowInstance) {
    Write-Log "Environment variables for authentication (TENANT_ID, SERVICENOW_INSTANCE, etc.) are missing. Using mock data for demonstration." "WARN"
}

# 2. Authenticate with Microsoft Graph API
Write-Log "Authenticating with Microsoft Graph API..."
$GraphTokenUrl = "https://login.microsoftonline.com/$($Config.TenantId)/oauth2/v2.0/token"
$GraphBody = @{
    client_id     = $Config.ClientId
    client_secret = $Config.ClientSecret
    scope         = "https://graph.microsoft.com/.default"
    grant_type    = "client_credentials"
}

try {
    # Only run the API call if credentials exist, otherwise simulate
    if ($Config.TenantId) {
        $GraphTokenResponse = Invoke-RestMethod -Method Post -Uri $GraphTokenUrl -Body $GraphBody -ErrorAction Stop
        $GraphToken = $GraphTokenResponse.access_token
        Write-Log "Successfully acquired Microsoft Graph API token."
    } else {
        $GraphToken = "SimulatedToken"
        Write-Log "Simulated Microsoft Graph API token acquisition."
    }
} catch {
    Write-Log "Failed to acquire Microsoft Graph token: $($_.Exception.Message)" "ERROR"
    exit
}

# 3. Fetch DLP Alerts from Microsoft Graph Security API
$StartTime = (Get-Date).AddHours(-$HoursToQuery).ToString("yyyy-MM-ddTHH:mm:ssZ")
Write-Log "Fetching DLP Alerts generated since $StartTime..."

# Example Graph API endpoint for Security Alerts (filtered by DLP provider)
$GraphAlertsUrl = "https://graph.microsoft.com/v1.0/security/alerts_v2?`$filter=providerId eq 'O365Dlp' and createdDateTime ge $StartTime"

$Headers = @{
    "Authorization" = "Bearer $GraphToken"
    "Content-Type"  = "application/json"
}

$DlpAlerts = @()

try {
    if ($Config.TenantId) {
        $AlertsResponse = Invoke-RestMethod -Method Get -Uri $GraphAlertsUrl -Headers $Headers -ErrorAction Stop
        $DlpAlerts = $AlertsResponse.value
    } else {
        # Simulate an alert
        $DlpAlerts = @(
            @{
                id = "alert-12345"
                title = "DLP Policy Match: Enterprise-DLP-US-Financial-PII"
                severity = "High"
                description = "User attempted to share a document containing 15 Credit Card Numbers externally."
                createdDateTime = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
                userPrincipalName = "user@domain.com"
            }
        )
        Write-Log "Using simulated DLP alert data."
    }
    Write-Log "Found $($DlpAlerts.Count) new DLP alert(s)."
} catch {
    Write-Log "Failed to fetch DLP alerts: $($_.Exception.Message)" "ERROR"
    exit
}

if ($DlpAlerts.Count -eq 0) {
    Write-Log "No new DLP alerts found. Exiting."
    exit
}

# 4. Authenticate and Push to ServiceNow
Write-Log "Preparing to push alerts to ServiceNow..."

$ServiceNowUrl = "https://$($Config.ServiceNowInstance).service-now.com/api/now/table/incident"
$SnAuthBytes = [System.Text.Encoding]::ASCII.GetBytes("$($Config.ServiceNowUser):$($Config.ServiceNowPassword)")
$SnBase64Auth = [System.Convert]::ToBase64String($SnAuthBytes)

$SnHeaders = @{
    "Authorization" = "Basic $SnBase64Auth"
    "Content-Type"  = "application/json"
    "Accept"        = "application/json"
}

foreach ($Alert in $DlpAlerts) {
    Write-Log "Processing Alert ID: $($Alert.id)"

    # Map Purview Severity to ServiceNow Urgency/Impact
    # 1=High, 2=Medium, 3=Low
    $Urgency = 2
    if ($Alert.severity -eq "High") { $Urgency = 1 }
    elseif ($Alert.severity -eq "Low") { $Urgency = 3 }

    $IncidentBody = @{
        caller_id         = $Alert.userPrincipalName
        short_description = "Purview DLP Alert: $($Alert.title)"
        description       = "A Microsoft Purview DLP alert was triggered.`n`nDetails:`n- Alert ID: $($Alert.id)`n- Severity: $($Alert.severity)`n- Timestamp: $($Alert.createdDateTime)`n- User: $($Alert.userPrincipalName)`n- Description: $($Alert.description)`n`nNote: Incident report details have been sent to the designated DLP Shared Mailbox."
        urgency           = $Urgency
        impact            = $Urgency
        category          = "Security"
        subcategory       = "Data Loss Prevention"
    } | ConvertTo-Json

    try {
        if ($Config.ServiceNowInstance) {
            $IncidentResponse = Invoke-RestMethod -Method Post -Uri $ServiceNowUrl -Headers $SnHeaders -Body $IncidentBody -ErrorAction Stop
            Write-Log "Successfully created ServiceNow Incident: $($IncidentResponse.result.number) for Alert: $($Alert.id)"
        } else {
            Write-Log "Simulated creating ServiceNow Incident for Alert: $($Alert.id). Payload: $IncidentBody"
        }
    } catch {
        Write-Log "Failed to create ServiceNow Incident for Alert $($Alert.id): $($_.Exception.Message)" "ERROR"
    }
}

Write-Log "DLP to ServiceNow Synchronization Complete."
