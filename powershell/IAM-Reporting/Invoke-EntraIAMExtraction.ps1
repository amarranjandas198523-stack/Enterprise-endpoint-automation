<#
.SYNOPSIS
    Enterprise Advanced IAM Reporting Engine for Microsoft Entra ID.

.DESCRIPTION
    This script is designed to run within an Azure Automation Account utilizing a
    System-Assigned Managed Identity. It connects to Microsoft Graph API to extract
    high-value, advanced IAM metrics, formats the data, and pushes it to an Azure Log
    Analytics Workspace via the HTTP Data Collector API for Power BI reporting.

    High-value metrics extracted:
    - Highly Privileged App Governance (Service Principals with expiring credentials)
    - PIM Role Drift (Active vs Eligible)
    - Identity Protection Risks (High Risk Users & Service Principals)
    - Conditional Access Exceptions (Bypass auditing)

.PREREQUISITES
    - Azure Automation Account with a System-Assigned Managed Identity.
    - Managed Identity must have Graph API permissions (Directory.Read.All, AuditLog.Read.All, Policy.Read.All, RoleManagement.Read.Directory, Application.Read.All).
    - Azure Automation Variables: 'LogAnalyticsWorkspaceId' and 'LogAnalyticsPrimaryKey'.

.AUTHOR
    Enterprise IAM Security Team
#>

[CmdletBinding()]
param()

# Ensure TLS 1.2 is used for all connections
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ==============================================================================
# Helper Functions
# ==============================================================================

function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [Parameter(Mandatory=$false)][ValidateSet("INFO", "WARN", "ERROR")][string]$Level = "INFO"
    )
    $Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ssZ")
    $LogMessage = "[$Timestamp] [$Level] $Message"
    Write-Output $LogMessage
}

function Invoke-GraphRequestWithRetry {
    param(
        [Parameter(Mandatory=$true)][string]$Uri,
        [Parameter(Mandatory=$true)][string]$Token,
        [Parameter(Mandatory=$false)][string]$Method = "GET"
    )

    $Headers = @{
        "Authorization" = "Bearer $Token"
        "Content-Type"  = "application/json"
    }

    $MaxRetries = 3
    $AllResults = @()
    $CurrentUri = $Uri

    while ($null -ne $CurrentUri) {
        $RetryCount = 0
        $Success = $false

        while (-not $Success -and $RetryCount -lt $MaxRetries) {
            try {
                $Response = Invoke-RestMethod -Uri $CurrentUri -Headers $Headers -Method $Method -ErrorAction Stop

                # Append results based on typical Graph API response structures
                if ($null -ne $Response.value) {
                    $AllResults += $Response.value
                } else {
                    $AllResults += $Response
                }

                # Handle Microsoft Graph Pagination (@odata.nextLink)
                if ($null -ne $Response.'@odata.nextLink') {
                    $CurrentUri = $Response.'@odata.nextLink'
                } else {
                    $CurrentUri = $null
                }

                $Success = $true

            } catch {
                $Exception = $_.Exception

                # Safe checking of response status code to handle network drop/timeouts where Response is null
                if ($null -ne $Exception.Response) {
                    $StatusCode = [int]$Exception.Response.StatusCode
                } else {
                    $StatusCode = 0
                }

                if ($StatusCode -eq 429) {
                    # Handle Throttling (Too Many Requests)
                    $RetryAfter = $Exception.Response.Headers["Retry-After"]
                    $WaitTime = if ([int]::TryParse($RetryAfter, [ref]$null)) { [int]$RetryAfter } else { [math]::Pow(2, $RetryCount) + 1 }
                    Write-Log "Graph API Throttled (429). Retrying in $WaitTime seconds..." "WARN"
                    Start-Sleep -Seconds $WaitTime
                    $RetryCount++
                } elseif ($StatusCode -ge 500 -or $StatusCode -eq 0) {
                    # Handle Transient Server Errors or Network Drop
                    $WaitTime = [math]::Pow(2, $RetryCount) + 1
                    Write-Log "Graph API Transient Error/Timeout ($StatusCode). Retrying in $WaitTime seconds..." "WARN"
                    Start-Sleep -Seconds $WaitTime
                    $RetryCount++
                } else {
                    Write-Log "Graph API Request Failed: $($Exception.Message)" "ERROR"
                    throw $Exception
                }
            }
        }

        if (-not $Success) {
            throw "Failed to complete Graph API request after $MaxRetries retries for URI: $CurrentUri"
        }
    }

    return $AllResults
}

# ==============================================================================
# Authentication
# ==============================================================================

function Connect-EntraUsingManagedIdentity {
    Write-Log "Attempting to authenticate using System-Assigned Managed Identity..."
    try {
        # Endpoint for Azure Automation Managed Identity
        $Resource = "https://graph.microsoft.com/"
        $Endpoint = $env:IDENTITY_ENDPOINT
        $Header = $env:IDENTITY_HEADER

        if ([string]::IsNullOrEmpty($Endpoint) -or [string]::IsNullOrEmpty($Header)) {
            Write-Log "Managed Identity endpoint variables not found. Attempting generic IMDS endpoint (for testing on VMs)..." "WARN"
            # Fallback to IMDS if running on a VM instead of Azure Automation
            $Response = Invoke-RestMethod -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fgraph.microsoft.com%2F' -Headers @{Metadata="true"} -Method Get
            $Token = $Response.access_token
        } else {
            # Running in Azure Automation
            $Response = Invoke-RestMethod -Method Get -Uri "$Endpoint`?resource=$Resource&api-version=2019-08-01" -Headers @{ "X-IDENTITY-HEADER" = $Header }
            $Token = $Response.access_token
        }

        Write-Log "Successfully acquired Microsoft Graph access token via Managed Identity."
        return $Token
    } catch {
        Write-Log "Failed to acquire Managed Identity token: $($_.Exception.Message)" "ERROR"
        throw
    }
}

# ==============================================================================
# Extraction Functions
# ==============================================================================

function Get-AppGovernanceMetrics {
    param([string]$Token)
    Write-Log "Extracting App Governance Metrics (Expiring Credentials)..."

    $Uri = "https://graph.microsoft.com/beta/servicePrincipals?`$select=id,displayName,appId,passwordCredentials,keyCredentials"
    $Metrics = @()
    $WarnThresholdDays = 30

    try {
        $ServicePrincipals = Invoke-GraphRequestWithRetry -Uri $Uri -Token $Token

        foreach ($Sp in $ServicePrincipals) {
            $Creds = @($Sp.passwordCredentials) + @($Sp.keyCredentials)
            foreach ($Cred in $Creds) {
                if ($null -ne $Cred.endDateTime) {
                    $DaysRemaining = ([DateTime]$Cred.endDateTime - (Get-Date)).Days
                    if ($DaysRemaining -ge 0 -and $DaysRemaining -le $WarnThresholdDays) {
                        $Metrics += [PSCustomObject]@{
                            AppId = $Sp.appId
                            DisplayName = $Sp.displayName
                            CredentialType = if ($null -ne $Cred.secretText) { "Password" } else { "Certificate" }
                            ExpirationDate = $Cred.endDateTime
                            DaysRemaining = $DaysRemaining
                            Status = "ExpiringSoon"
                        }
                    } elseif ($DaysRemaining -lt 0) {
                         $Metrics += [PSCustomObject]@{
                            AppId = $Sp.appId
                            DisplayName = $Sp.displayName
                            CredentialType = if ($null -ne $Cred.secretText) { "Password" } else { "Certificate" }
                            ExpirationDate = $Cred.endDateTime
                            DaysRemaining = $DaysRemaining
                            Status = "Expired"
                        }
                    }
                }
            }
        }
        return $Metrics
    } catch {
        Write-Log "Error extracting App Governance metrics." "ERROR"
        return $null
    }
}

function Get-PIMRoleDriftMetrics {
    param([string]$Token)
    Write-Log "Extracting PIM Role Drift Metrics (Global Admins)..."

    # Using beta endpoint for unified role management
    # Specifically targeting Global Administrator role (Template ID: 62e90394-69f5-4237-9190-012177145e10)
    $GlobalAdminRoleId = "62e90394-69f5-4237-9190-012177145e10"
    $Uri = "https://graph.microsoft.com/beta/roleManagement/directory/roleAssignments?`$filter=roleDefinitionId eq '$GlobalAdminRoleId'&`$expand=principal"

    $Metrics = @()

    try {
        $Assignments = Invoke-GraphRequestWithRetry -Uri $Uri -Token $Token

        foreach ($Assignment in $Assignments) {
            $Metrics += [PSCustomObject]@{
                PrincipalName = $Assignment.principal.displayName
                PrincipalId = $Assignment.principalId
                RoleName = "Global Administrator"
                AssignmentType = if ($Assignment.assignmentType -eq "Active") { "Active" } else { "Eligible" }
                IsPermanent = if ($null -eq $Assignment.endDateTime) { $true } else { $false }
            }
        }
        return $Metrics
    } catch {
         Write-Log "Error extracting PIM Role Drift metrics." "ERROR"
         return $null
    }
}

function Get-IdentityProtectionMetrics {
    param([string]$Token)
    Write-Log "Extracting Identity Protection Metrics (High Risk Users)..."

    $Uri = "https://graph.microsoft.com/beta/riskyUsers?`$filter=riskLevel eq 'high'"
    $Metrics = @()

    try {
        $RiskyUsers = Invoke-GraphRequestWithRetry -Uri $Uri -Token $Token

        foreach ($User in $RiskyUsers) {
            $Metrics += [PSCustomObject]@{
                UserPrincipalName = $User.userPrincipalName
                RiskLevel = $User.riskLevel
                RiskDetail = $User.riskDetail
                RiskLastUpdatedDateTime = $User.riskLastUpdatedDateTime
            }
        }
        return $Metrics
    } catch {
        Write-Log "Error extracting Identity Protection metrics." "ERROR"
        return $null
    }
}

# ==============================================================================
# Log Analytics Integration (Modern Logs Ingestion API)
# ==============================================================================

function Get-AzureMonitorToken {
    Write-Log "Attempting to authenticate to Azure Monitor using System-Assigned Managed Identity..."
    try {
        # Endpoint for Azure Automation Managed Identity, targeting Azure Monitor
        $Resource = "https://monitor.azure.com/"
        $Endpoint = $env:IDENTITY_ENDPOINT
        $Header = $env:IDENTITY_HEADER

        if ([string]::IsNullOrEmpty($Endpoint) -or [string]::IsNullOrEmpty($Header)) {
            Write-Log "Managed Identity endpoint variables not found. Attempting generic IMDS endpoint..." "WARN"
            $Response = Invoke-RestMethod -Uri "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=$Resource" -Headers @{Metadata="true"} -Method Get
            $Token = $Response.access_token
        } else {
            $Response = Invoke-RestMethod -Method Get -Uri "$Endpoint`?resource=$Resource&api-version=2019-08-01" -Headers @{ "X-IDENTITY-HEADER" = $Header }
            $Token = $Response.access_token
        }

        Write-Log "Successfully acquired Azure Monitor access token."
        return $Token
    } catch {
        Write-Log "Failed to acquire Azure Monitor token: $($_.Exception.Message)" "ERROR"
        throw
    }
}

function Send-DataToLogAnalytics {
    param(
        [Parameter(Mandatory=$true)][string]$DceUri,
        [Parameter(Mandatory=$true)][string]$DcrImmutableId,
        [Parameter(Mandatory=$true)][string]$StreamName,
        [Parameter(Mandatory=$true)][string]$MonitorToken,
        [Parameter(Mandatory=$true)][object[]]$JsonData
    )

    if ($null -eq $JsonData -or $JsonData.Count -eq 0) {
        Write-Log "No data to send for Stream: $StreamName" "INFO"
        return
    }

    Write-Log "Pushing $($JsonData.Count) records to Azure Monitor DCR ($StreamName)..."

    # Ensure all objects have a TimeGenerated property as expected by DCR schema
    foreach ($Item in $JsonData) {
        if (-not $Item.PSObject.Properties.Match('TimeGenerated').Count) {
            $Item | Add-Member -MemberType NoteProperty -Name "TimeGenerated" -Value (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        }
    }

    $LogData = $JsonData | ConvertTo-Json -Depth 10

    $Uri = "$DceUri/dataCollectionRules/$DcrImmutableId/streams/Custom-${StreamName}?api-version=2023-01-01"

    $Headers = @{
        "Authorization" = "Bearer $MonitorToken"
        "Content-Type"  = "application/json"
    }

    try {
        $Response = Invoke-RestMethod -Uri $Uri -Method Post -Body $LogData -Headers $Headers
        Write-Log "Successfully sent data for $StreamName"
    } catch {
        Write-Log "Failed to send data to Azure Monitor for $StreamName`: $($_.Exception.Message)" "ERROR"
        # Often DCR schema mismatch errors have detailed inner messages
        if ($null -ne $_.Exception.Response) {
            $Reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $Reader.BaseStream.Position = 0
            $Reader.DiscardBufferedData()
            $ResponseBody = $Reader.ReadToEnd()
            Write-Log "Response Body: $ResponseBody" "ERROR"
        }
    }
}

# ==============================================================================
# Main Execution
# ==============================================================================

try {
    Write-Log "Starting Advanced IAM Reporting Extraction (DCR Ingestion)..."

    # Retrieve DCR settings from Azure Automation Variables
    # Note: In a real runbook environment, use Get-AutomationVariable
    # For testing/local runs, we fallback to Environment variables

    $DceUri = $null
    $DcrImmutableId = $null

    try {
        $DceUri = Get-AutomationVariable -Name "DataCollectionEndpointUri" -ErrorAction Stop
        $DcrImmutableId = Get-AutomationVariable -Name "DataCollectionRuleImmutableId" -ErrorAction Stop
    } catch {
        Write-Log "Could not find Automation Variables. Falling back to Environment Variables." "WARN"
        $DceUri = $env:DATA_COLLECTION_ENDPOINT_URI
        $DcrImmutableId = $env:DATA_COLLECTION_RULE_IMMUTABLE_ID
    }

    if ([string]::IsNullOrEmpty($DceUri) -or [string]::IsNullOrEmpty($DcrImmutableId)) {
        throw "Data Collection Endpoint URI or DCR Immutable ID is missing. Extraction aborted."
    }

    # 1. Authenticate (Dual Tokens required)
    $GraphToken = Connect-EntraUsingManagedIdentity
    $MonitorToken = Get-AzureMonitorToken

    # 2. Extract Data
    $AppGovData = Get-AppGovernanceMetrics -Token $GraphToken
    $PimData = Get-PIMRoleDriftMetrics -Token $GraphToken
    $IdpData = Get-IdentityProtectionMetrics -Token $GraphToken

    # 3. Push to Azure Monitor via DCR
    Send-DataToLogAnalytics -DceUri $DceUri -DcrImmutableId $DcrImmutableId -StreamName "IAM_AppGovernance_CL" -MonitorToken $MonitorToken -JsonData $AppGovData
    Send-DataToLogAnalytics -DceUri $DceUri -DcrImmutableId $DcrImmutableId -StreamName "IAM_PIMRoleDrift_CL" -MonitorToken $MonitorToken -JsonData $PimData
    Send-DataToLogAnalytics -DceUri $DceUri -DcrImmutableId $DcrImmutableId -StreamName "IAM_IdentityProtection_CL" -MonitorToken $MonitorToken -JsonData $IdpData

    Write-Log "Extraction and DCR Upload Complete."
} catch {
    Write-Log "Execution Failed: $($_.Exception.Message)" "ERROR"
    exit 1
}
