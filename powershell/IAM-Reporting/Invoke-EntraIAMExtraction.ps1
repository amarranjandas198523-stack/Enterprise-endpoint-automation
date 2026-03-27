<#
.SYNOPSIS
    Enterprise Advanced IAM Reporting Engine for Microsoft Entra ID.

.DESCRIPTION
    This script is designed to run within an Azure Automation Account utilizing a
    System-Assigned Managed Identity. It connects to Microsoft Graph API to extract
    high-value, advanced IAM metrics, evaluates risk scores, and pushes them to Azure Monitor
    via the modern Logs Ingestion API (DCR) for Power BI reporting.

    High-value metrics extracted:
    - Highly Privileged App Governance (Expiring credentials)
    - PIM Role Drift (Active vs Eligible)
    - Identity Protection Risks (High Risk Users & Service Principals)
    - Conditional Access Exceptions
    - Dormant Accounts (>90 days inactive)
    - Guest User Risks
    - App Consent Anomalies (High-Privilege OAuth Scopes)
    - Token Lifetime Policies

.PREREQUISITES
    - Azure Automation Account with a System-Assigned Managed Identity.
    - Managed Identity must have Graph API permissions (Directory.Read.All, AuditLog.Read.All, Policy.Read.All, RoleManagement.Read.Directory, Application.Read.All).
    - Azure Automation Variables: 'DataCollectionEndpointUri' and 'DataCollectionRuleImmutableId'.

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

$Global:RunCorrelationId = [guid]::NewGuid().ToString()

function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [Parameter(Mandatory=$false)][ValidateSet("INFO", "WARN", "ERROR")][string]$Level = "INFO"
    )
    $LogData = @{
        Timestamp     = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        Level         = $Level
        CorrelationId = $Global:RunCorrelationId
        Message       = $Message
    }
    Write-Output ($LogData | ConvertTo-Json -Compress)
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

                    [int]$ParsedWaitTime = 0
                    if ([int]::TryParse($RetryAfter, [ref]$ParsedWaitTime)) {
                        $WaitTime = $ParsedWaitTime
                    } else {
                        $WaitTime = [math]::Pow(2, $RetryCount) + 1
                    }

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
# Authentication & Token Management
# ==============================================================================

function Connect-EntraUsingManagedIdentity {
    # Stub for backward compatibility if ever called directly from another module
    return Get-GraphToken
}

$Global:GraphToken = $null
$Global:GraphTokenExpiry = $null
$Global:MonitorToken = $null
$Global:MonitorTokenExpiry = $null

function Get-ManagedIdentityToken {
    param([string]$ResourceUrl)

    $Endpoint = $env:IDENTITY_ENDPOINT
    $Header = $env:IDENTITY_HEADER

    if ([string]::IsNullOrEmpty($Endpoint) -or [string]::IsNullOrEmpty($Header)) {
        Write-Log "Using IMDS for Managed Identity ($ResourceUrl)..."
        $Response = Invoke-RestMethod -Uri "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=$ResourceUrl" -Headers @{Metadata="true"} -Method Get
    } else {
        $Response = Invoke-RestMethod -Method Get -Uri "$Endpoint`?resource=$ResourceUrl&api-version=2019-08-01" -Headers @{ "X-IDENTITY-HEADER" = $Header }
    }

    return [PSCustomObject]@{
        Token = $Response.access_token
        # Standard Oauth response usually has expires_on (epoch time)
        ExpiresOn = [DateTimeOffset]::FromUnixTimeSeconds($Response.expires_on).UtcDateTime
    }
}

function Get-GraphToken {
    if ($null -eq $Global:GraphToken -or (Get-Date).ToUniversalTime() -ge $Global:GraphTokenExpiry.AddMinutes(-5)) {
        Write-Log "Acquiring/Refreshing Microsoft Graph access token..."
        try {
            $Result = Get-ManagedIdentityToken -ResourceUrl "https://graph.microsoft.com/"
            $Global:GraphToken = $Result.Token
            $Global:GraphTokenExpiry = $Result.ExpiresOn
            Write-Log "Graph Token acquired. Expires: $($Global:GraphTokenExpiry.ToString("yyyy-MM-dd HH:mm:ssZ"))"
        } catch {
            Write-Log "Failed to acquire Graph token: $($_.Exception.Message)" "ERROR"
            throw
        }
    }
    return $Global:GraphToken
}

function Get-AzureMonitorToken {
    if ($null -eq $Global:MonitorToken -or (Get-Date).ToUniversalTime() -ge $Global:MonitorTokenExpiry.AddMinutes(-5)) {
        Write-Log "Acquiring/Refreshing Azure Monitor access token..."
        try {
            $Result = Get-ManagedIdentityToken -ResourceUrl "https://monitor.azure.com/"
            $Global:MonitorToken = $Result.Token
            $Global:MonitorTokenExpiry = $Result.ExpiresOn
            Write-Log "Monitor Token acquired. Expires: $($Global:MonitorTokenExpiry.ToString("yyyy-MM-dd HH:mm:ssZ"))"
        } catch {
            Write-Log "Failed to acquire Azure Monitor token: $($_.Exception.Message)" "ERROR"
            throw
        }
    }
    return $Global:MonitorToken
}

# ==============================================================================
# Security & Pre-Flight Validation
# ==============================================================================

function Validate-GraphPermissions {
    Write-Log "Validating necessary Microsoft Graph API Application permissions (Fail-Fast)..."
    try {
        $Uri = "https://graph.microsoft.com/v1.0/servicePrincipals?`$top=1"
        $null = Invoke-GraphRequestWithRetryWrapper -Uri $Uri
        Write-Log "Permission validation successful."
    } catch {
        Write-Log "CRITICAL: Service Principal does not have sufficient Microsoft Graph permissions." "ERROR"
        throw $_
    }
}

# ==============================================================================
# Extraction Functions
# ==============================================================================

$Global:ApiCallCount = 0

function Get-DeterministicHash {
    param([string]$InputString)
    $Bytes = [System.Text.Encoding]::UTF8.GetBytes($InputString)
    $Sha256 = [System.Security.Cryptography.SHA256]::Create()
    $HashBytes = $Sha256.ComputeHash($Bytes)
    $HashString = [BitConverter]::ToString($HashBytes) -replace '-'
    return $HashString.ToLower()
}

function Invoke-GraphRequestWithRetryWrapper {
    param(
        [Parameter(Mandatory=$true)][string]$Uri,
        [Parameter(Mandatory=$false)][string]$Method = "GET"
    )
    $Global:ApiCallCount++
    $Token = Get-GraphToken
    return Invoke-GraphRequestWithRetry -Uri $Uri -Token $Token -Method $Method
}

function Get-AppGovernanceMetrics {
    Write-Log "Extracting App Governance Metrics (Expiring Credentials)..."

    $Uri = "https://graph.microsoft.com/v1.0/servicePrincipals?`$select=id,displayName,appId,passwordCredentials,keyCredentials"
    $Metrics = @()
    $WarnThresholdDays = 30

    try {
        $ServicePrincipals = Invoke-GraphRequestWithRetryWrapper -Uri $Uri

        foreach ($Sp in $ServicePrincipals) {
            $Creds = @($Sp.passwordCredentials) + @($Sp.keyCredentials)
            foreach ($Cred in $Creds) {
                if ($null -ne $Cred.endDateTime) {
                    $DaysRemaining = ([DateTime]$Cred.endDateTime - (Get-Date)).Days

                    # Safer Credential Type detection since secretText is omitted by Graph API
                    $CredType = if ($null -ne $Cred.customKeyIdentifier) { "Certificate" } else { "Password" }

                    if ($DaysRemaining -ge 0 -and $DaysRemaining -le $WarnThresholdDays) {
                        $RecordId = Get-DeterministicHash -InputString "$($Sp.appId)-$CredType-$($Cred.endDateTime)"
                        $RiskScore = if ($DaysRemaining -le 7) { 70 } elseif ($DaysRemaining -le 14) { 50 } else { 30 }
                        $Metrics += [PSCustomObject]@{
                            RecordId = $RecordId
                            RiskScore = $RiskScore
                            AppId = $Sp.appId
                            DisplayName = $Sp.displayName
                            CredentialType = $CredType
                            ExpirationDate = $Cred.endDateTime
                            DaysRemaining = $DaysRemaining
                            Status = "ExpiringSoon"
                        }
                    } elseif ($DaysRemaining -lt 0) {
                        $RecordId = Get-DeterministicHash -InputString "$($Sp.appId)-$CredType-$($Cred.endDateTime)"
                         $Metrics += [PSCustomObject]@{
                            RecordId = $RecordId
                            RiskScore = 90
                            AppId = $Sp.appId
                            DisplayName = $Sp.displayName
                            CredentialType = $CredType
                            ExpirationDate = $Cred.endDateTime
                            DaysRemaining = $DaysRemaining
                            Status = "Expired"
                        }
                    }
                }
            }
        }
        Write-Log "Found $($Metrics.Count) expiring/expired credentials."
        return $Metrics
    } catch {
        Write-Log "Error extracting App Governance metrics." "ERROR"
        return $null
    }
}

function Get-PIMRoleDriftMetrics {
    Write-Log "Extracting PIM Role Drift Metrics (Global Admins)..."

    # Targeting Global Administrator role
    $GlobalAdminRoleId = "62e90394-69f5-4237-9190-012177145e10"
    $BaseUri = "https://graph.microsoft.com/v1.0/roleManagement/directory"

    $Metrics = @()

    try {
        # Fetch Active Assignments
        $ActiveUri = "$BaseUri/roleAssignmentSchedules?`$filter=roleDefinitionId eq '$GlobalAdminRoleId'&`$expand=principal"
        $ActiveAssignments = Invoke-GraphRequestWithRetryWrapper -Uri $ActiveUri

        foreach ($Assignment in $ActiveAssignments) {
            $RecordId = Get-DeterministicHash -InputString "Active-$($Assignment.id)"
            $IsPerm = if ($null -eq $Assignment.scheduleInfo.expiration.endDateTime) { $true } else { $false }
            $RiskScore = if ($IsPerm) { 100 } else { 60 } # Active Permanent GA is highest risk
            $Metrics += [PSCustomObject]@{
                RecordId = $RecordId
                RiskScore = $RiskScore
                PrincipalName = if ($null -ne $Assignment.principal.displayName) { $Assignment.principal.displayName } else { "Unknown" }
                PrincipalId = $Assignment.principalId
                RoleName = "Global Administrator"
                AssignmentType = "Active"
                IsPermanent = $IsPerm
                ScheduleId = $Assignment.id
            }
        }

        # Fetch Eligible Assignments
        $EligibleUri = "$BaseUri/roleEligibilitySchedules?`$filter=roleDefinitionId eq '$GlobalAdminRoleId'&`$expand=principal"
        $EligibleAssignments = Invoke-GraphRequestWithRetryWrapper -Uri $EligibleUri

        foreach ($Assignment in $EligibleAssignments) {
            $RecordId = Get-DeterministicHash -InputString "Eligible-$($Assignment.id)"
            $IsPerm = if ($null -eq $Assignment.scheduleInfo.expiration.endDateTime) { $true } else { $false }
            $RiskScore = if ($IsPerm) { 80 } else { 40 } # Eligible Permanent is very risky
            $Metrics += [PSCustomObject]@{
                RecordId = $RecordId
                RiskScore = $RiskScore
                PrincipalName = if ($null -ne $Assignment.principal.displayName) { $Assignment.principal.displayName } else { "Unknown" }
                PrincipalId = $Assignment.principalId
                RoleName = "Global Administrator"
                AssignmentType = "Eligible"
                IsPermanent = $IsPerm
                ScheduleId = $Assignment.id
            }
        }

        Write-Log "Found $($Metrics.Count) PIM schedules for Global Admin."
        return $Metrics
    } catch {
         Write-Log "Error extracting PIM Role Drift metrics: $($_.Exception.Message)" "ERROR"
         return $null
    }
}

function Get-IdentityProtectionMetrics {
    Write-Log "Extracting Identity Protection Metrics (High Risk Users)..."

    $Uri = "https://graph.microsoft.com/v1.0/identityProtection/riskyUsers?`$filter=riskLevel eq 'high'"
    $Metrics = @()

    try {
        $RiskyUsers = Invoke-GraphRequestWithRetryWrapper -Uri $Uri

        foreach ($User in $RiskyUsers) {
            $RecordId = Get-DeterministicHash -InputString "$($User.userPrincipalName)-$($User.riskLastUpdatedDateTime)"
            $Metrics += [PSCustomObject]@{
                RecordId = $RecordId
                RiskScore = 95
                UserPrincipalName = $User.userPrincipalName
                RiskLevel = $User.riskLevel
                RiskDetail = $User.riskDetail
                RiskLastUpdatedDateTime = $User.riskLastUpdatedDateTime
            }
        }
        Write-Log "Found $($Metrics.Count) high risk users."
        return $Metrics
    } catch {
        Write-Log "Error extracting Identity Protection User metrics: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

function Get-RiskyServicePrincipalsMetrics {
    Write-Log "Extracting Identity Protection Metrics (High Risk Service Principals)..."

    $Uri = "https://graph.microsoft.com/v1.0/identityProtection/riskyServicePrincipals?`$filter=riskLevel eq 'high'"
    $Metrics = @()

    try {
        $RiskySPs = Invoke-GraphRequestWithRetryWrapper -Uri $Uri

        foreach ($Sp in $RiskySPs) {
            $RecordId = Get-DeterministicHash -InputString "$($Sp.appId)-$($Sp.riskLastUpdatedDateTime)"
            $Metrics += [PSCustomObject]@{
                RecordId = $RecordId
                RiskScore = 95
                AppId = $Sp.appId
                DisplayName = $Sp.displayName
                RiskLevel = $Sp.riskLevel
                RiskDetail = $Sp.riskDetail
                RiskLastUpdatedDateTime = $Sp.riskLastUpdatedDateTime
            }
        }
        Write-Log "Found $($Metrics.Count) high risk service principals."
        return $Metrics
    } catch {
        Write-Log "Error extracting Identity Protection SP metrics: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

function Get-DormantAccountsMetrics {
    Write-Log "Extracting Dormant Accounts Metrics (>90 days inactive)..."

    $ThresholdDate = (Get-Date).AddDays(-90).ToString("yyyy-MM-ddTHH:mm:ssZ")
    # Utilizing signInActivity (requires AuditLog.Read.All and Directory.Read.All)
    $Uri = "https://graph.microsoft.com/v1.0/users?`$select=id,userPrincipalName,signInActivity,accountEnabled&`$filter=accountEnabled eq true"

    $Metrics = @()

    try {
        $Users = Invoke-GraphRequestWithRetryWrapper -Uri $Uri

        foreach ($User in $Users) {
            $LastSignIn = $null
            if ($null -ne $User.signInActivity -and $null -ne $User.signInActivity.lastSignInDateTime) {
                $LastSignIn = $User.signInActivity.lastSignInDateTime
            }

            # If they have signed in, and it's older than threshold OR they have never signed in
            if ($null -ne $LastSignIn) {
                $DaysInactive = ([DateTime]$ThresholdDate - [DateTime]$LastSignIn).Days
                if ($DaysInactive -gt 0) {
                     $RecordId = Get-DeterministicHash -InputString "$($User.userPrincipalName)-$LastSignIn"
                     $TotalInactive = $DaysInactive + 90
                     $RiskScore = if ($TotalInactive -ge 365) { 90 } elseif ($TotalInactive -ge 180) { 75 } else { 50 }
                     $Metrics += [PSCustomObject]@{
                        RecordId = $RecordId
                        RiskScore = $RiskScore
                        UserPrincipalName = $User.userPrincipalName
                        LastSignInDateTime = $LastSignIn
                        DaysInactive = $TotalInactive
                     }
                }
            } else {
                # Never signed in, but account is enabled. We will flag them.
                $RecordId = Get-DeterministicHash -InputString "$($User.userPrincipalName)-NeverSignedIn"
                $Metrics += [PSCustomObject]@{
                    RecordId = $RecordId
                    RiskScore = 60
                    UserPrincipalName = $User.userPrincipalName
                    LastSignInDateTime = $null
                    DaysInactive = 999
                }
            }
        }
        Write-Log "Found $($Metrics.Count) active but dormant accounts."
        return $Metrics
    } catch {
        Write-Log "Error extracting Dormant Account metrics: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

function Get-GuestUserRiskMetrics {
    Write-Log "Extracting Guest/External User Metrics..."

    $Uri = "https://graph.microsoft.com/v1.0/users?`$filter=userType eq 'Guest'&`$select=id,userPrincipalName,createdDateTime,accountEnabled"
    $Metrics = @()

    try {
        $Guests = Invoke-GraphRequestWithRetryWrapper -Uri $Uri

        foreach ($Guest in $Guests) {
            $RecordId = Get-DeterministicHash -InputString "$($Guest.userPrincipalName)-$($Guest.accountEnabled)"
            $RiskScore = if ($Guest.accountEnabled) { 40 } else { 10 }
            $Metrics += [PSCustomObject]@{
                RecordId = $RecordId
                RiskScore = $RiskScore
                UserPrincipalName = $Guest.userPrincipalName
                AccountEnabled = $Guest.accountEnabled
                CreatedDateTime = $Guest.createdDateTime
            }
        }
        Write-Log "Found $($Metrics.Count) guest users."
        return $Metrics
    } catch {
        Write-Log "Error extracting Guest User metrics: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

function Get-AppConsentAnomaliesMetrics {
    Write-Log "Extracting App Consent Anomalies (High Privilege Grants)..."

    $Uri = "https://graph.microsoft.com/v1.0/oauth2PermissionGrants"
    $Metrics = @()
    # List of highly sensitive scopes that usually indicate high risk if granted widely
    $HighRiskScopes = @("Directory.ReadWrite.All", "RoleManagement.ReadWrite.Directory", "AppRoleAssignment.ReadWrite.All")

    try {
        $Grants = Invoke-GraphRequestWithRetryWrapper -Uri $Uri

        foreach ($Grant in $Grants) {
            $Scopes = $Grant.scope -split " "
            $RiskFound = $false
            $FoundScopes = @()
            foreach ($Scope in $Scopes) {
                if ($HighRiskScopes -contains $Scope) {
                    $RiskFound = $true
                    $FoundScopes += $Scope
                }
            }

            if ($RiskFound) {
                $RecordId = Get-DeterministicHash -InputString "$($Grant.id)-$($Grant.scope)"
                $RiskScore = if ($Grant.consentType -eq "AllPrincipals") { 100 } else { 85 }
                $Metrics += [PSCustomObject]@{
                    RecordId = $RecordId
                    RiskScore = $RiskScore
                    GrantId = $Grant.id
                    ClientId = $Grant.clientId
                    PrincipalId = if ($null -ne $Grant.principalId) { $Grant.principalId } else { "AllPrincipals" }
                    ConsentType = $Grant.consentType
                    HighRiskScopes = $FoundScopes -join ", "
                }
            }
        }
        Write-Log "Found $($Metrics.Count) anomalous app consent grants."
        return $Metrics
    } catch {
        Write-Log "Error extracting App Consent metrics: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

function Get-TokenLifetimePoliciesMetrics {
    Write-Log "Extracting Token Lifetime Policies..."

    $Uri = "https://graph.microsoft.com/v1.0/policies/tokenLifetimePolicies"
    $Metrics = @()

    try {
        $Policies = Invoke-GraphRequestWithRetryWrapper -Uri $Uri

        foreach ($Policy in $Policies) {
            $RecordId = Get-DeterministicHash -InputString "$($Policy.id)"
            $Metrics += [PSCustomObject]@{
                RecordId = $RecordId
                PolicyId = $Policy.id
                DisplayName = $Policy.displayName
                IsOrganizationDefault = $Policy.isOrganizationDefault
                Definition = $Policy.definition -join " | "
            }
        }
        Write-Log "Found $($Metrics.Count) token lifetime policies."
        return $Metrics
    } catch {
        Write-Log "Error extracting Token Lifetime Policy metrics: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

function Get-ConditionalAccessMetrics {
    Write-Log "Extracting Conditional Access Policy Status..."

    $Uri = "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies?`$select=id,displayName,state,conditions"
    $Metrics = @()

    try {
        $Policies = Invoke-GraphRequestWithRetryWrapper -Uri $Uri

        foreach ($Policy in $Policies) {
            $HasExceptions = $false
            if ($null -ne $Policy.conditions.users.excludeUsers -and $Policy.conditions.users.excludeUsers.Count -gt 0) {
                $HasExceptions = $true
            }
            if ($null -ne $Policy.conditions.users.excludeGroups -and $Policy.conditions.users.excludeGroups.Count -gt 0) {
                $HasExceptions = $true
            }

            $RecordId = Get-DeterministicHash -InputString "$($Policy.id)-$($Policy.state)-$HasExceptions"
            $RiskScore = 0
            if ($Policy.state -eq "disabled") { $RiskScore = 80 }
            elseif ($HasExceptions) { $RiskScore = 50 }
            else { $RiskScore = 10 }

            $Metrics += [PSCustomObject]@{
                RecordId = $RecordId
                RiskScore = $RiskScore
                PolicyName = $Policy.displayName
                State = $Policy.state
                HasExceptions = $HasExceptions
                CreatedDateTime = $Policy.createdDateTime
            }
        }
        Write-Log "Analyzed $($Metrics.Count) Conditional Access policies."
        return $Metrics
    } catch {
        Write-Log "Error extracting Conditional Access metrics: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

# ==============================================================================
# Log Analytics Integration (Modern Logs Ingestion API)
# ==============================================================================

# Function removed to use the cached version defined earlier

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

    # Use -InputObject to prevent PowerShell from unrolling single-item arrays
    $LogData = ConvertTo-Json -InputObject $JsonData -Depth 10 -Compress

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

    # 1. Pre-fetch initial tokens (Smart wrappers handle caching/refresh)
    $null = Get-GraphToken
    $null = Get-AzureMonitorToken

    # 2. Validate Permissions (Fail Fast)
    Validate-GraphPermissions

    # 3. Extract Data
    $StartTime = Get-Date
    $AppGovData = Get-AppGovernanceMetrics
    $PimData = Get-PIMRoleDriftMetrics
    $IdpData = Get-IdentityProtectionMetrics
    $IdpSpData = Get-RiskyServicePrincipalsMetrics
    $CaData = Get-ConditionalAccessMetrics
    $DormantData = Get-DormantAccountsMetrics
    $GuestData = Get-GuestUserRiskMetrics
    $ConsentData = Get-AppConsentAnomaliesMetrics
    $TokenPoliciesData = Get-TokenLifetimePoliciesMetrics

    # 4. Push to Azure Monitor via DCR
    # We dynamically fetch Monitor token inside Send-DataToLogAnalytics logic or here to ensure it isn't expired on long runs
    Send-DataToLogAnalytics -DceUri $DceUri -DcrImmutableId $DcrImmutableId -StreamName "IAM_AppGovernance_CL" -MonitorToken (Get-AzureMonitorToken) -JsonData $AppGovData
    Send-DataToLogAnalytics -DceUri $DceUri -DcrImmutableId $DcrImmutableId -StreamName "IAM_PIMRoleDrift_CL" -MonitorToken (Get-AzureMonitorToken) -JsonData $PimData
    Send-DataToLogAnalytics -DceUri $DceUri -DcrImmutableId $DcrImmutableId -StreamName "IAM_IdentityProtection_CL" -MonitorToken (Get-AzureMonitorToken) -JsonData $IdpData
    Send-DataToLogAnalytics -DceUri $DceUri -DcrImmutableId $DcrImmutableId -StreamName "IAM_RiskyServicePrincipals_CL" -MonitorToken (Get-AzureMonitorToken) -JsonData $IdpSpData
    Send-DataToLogAnalytics -DceUri $DceUri -DcrImmutableId $DcrImmutableId -StreamName "IAM_ConditionalAccess_CL" -MonitorToken (Get-AzureMonitorToken) -JsonData $CaData
    Send-DataToLogAnalytics -DceUri $DceUri -DcrImmutableId $DcrImmutableId -StreamName "IAM_DormantAccounts_CL" -MonitorToken (Get-AzureMonitorToken) -JsonData $DormantData
    Send-DataToLogAnalytics -DceUri $DceUri -DcrImmutableId $DcrImmutableId -StreamName "IAM_GuestUserRisk_CL" -MonitorToken (Get-AzureMonitorToken) -JsonData $GuestData
    Send-DataToLogAnalytics -DceUri $DceUri -DcrImmutableId $DcrImmutableId -StreamName "IAM_AppConsentAnomalies_CL" -MonitorToken (Get-AzureMonitorToken) -JsonData $ConsentData
    Send-DataToLogAnalytics -DceUri $DceUri -DcrImmutableId $DcrImmutableId -StreamName "IAM_TokenLifetimePolicies_CL" -MonitorToken (Get-AzureMonitorToken) -JsonData $TokenPoliciesData

    $Duration = ((Get-Date) - $StartTime).TotalSeconds
    Write-Log "Extraction and DCR Upload Complete. Total Duration: $([math]::Round($Duration, 2))s. Total Graph API Calls: $Global:ApiCallCount."
} catch {
    Write-Log "Execution Failed: $($_.Exception.Message)" "ERROR"
    exit 1
}
