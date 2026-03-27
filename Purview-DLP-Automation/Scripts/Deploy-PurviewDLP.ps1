# ==============================================================================================
# Script Name: Deploy-PurviewDLP.ps1
# Description: This script deploys an Enterprise-grade Microsoft Purview DLP implementation.
#              It creates Data Loss Prevention (DLP) policies for PII, Financial, Health (HIPAA),
#              and GDPR data. It enforces strict blocking for high-severity rules and allows
#              user overrides with business justifications for low-severity rules. It also
#              configures incident reports to be sent to a designated shared mailbox.
#
# Prerequisites:
#   - ExchangeOnlineManagement module installed (Install-Module ExchangeOnlineManagement).
#   - Connect to Security & Compliance PowerShell (Connect-IPPSSession).
# ==============================================================================================

[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [string]$IncidentReportMailbox = "dlp-alerts@yourdomain.com",

    [Parameter(Mandatory=$false)]
    [string[]]$PolicyWorkload = @("Exchange", "SharePoint", "OneDriveForBusiness", "EndpointDevices")
)

# Function to write timestamped logs
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$Timestamp] [$Level] $Message"
}

# Ensure ExchangeOnlineManagement module is available
if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
    Write-Log "ExchangeOnlineManagement module is not installed. Please install it first: Install-Module ExchangeOnlineManagement -Force" "ERROR"
    exit
}

# Connect to the IPPS Session (Security & Compliance)
# Note: In a true automated environment, use App-Only authentication (Service Principal + Certificate)
Write-Log "Connecting to Security & Compliance Center..."
try {
    Connect-IPPSSession -ErrorAction Stop
    Write-Log "Successfully connected to Security & Compliance."
} catch {
    Write-Log "Failed to connect to Security & Compliance. Please ensure you have the correct permissions and authentication." "ERROR"
    exit
}

# ----------------------------------------------------------------------------------------------
# 1. PII and Financial Data Policy (High Severity & Low Severity Rules)
# ----------------------------------------------------------------------------------------------
Write-Log "Creating US Financial & PII Data DLP Policy..."
$PiiPolicyName = "Enterprise-DLP-US-Financial-PII"
$PiiPolicyDescription = "Enterprise DLP policy for U.S. Financial Data and Personally Identifiable Information (PII)."

# Create the policy object
if (-not (Get-DlpCompliancePolicy -Identity $PiiPolicyName -ErrorAction SilentlyContinue)) {
    New-DlpCompliancePolicy -Name $PiiPolicyName -Comment $PiiPolicyDescription -ExchangeLocation All -SharePointLocation All -OneDriveLocation All -EndpointLocation All
    Write-Log "Created DLP Compliance Policy: $PiiPolicyName"
} else {
    Write-Log "DLP Compliance Policy '$PiiPolicyName' already exists." "WARN"
}

# Define High Severity Rule (Block, No Override)
# Matches >= 10 instances of U.S. SSN or Credit Card
$HighSeverityRuleName = "$PiiPolicyName-HighSeverity-Block"
if (-not (Get-DlpComplianceRule -Identity $HighSeverityRuleName -ErrorAction SilentlyContinue)) {
    New-DlpComplianceRule -Name $HighSeverityRuleName `
        -Policy $PiiPolicyName `
        -ContentContainsSensitiveInformation @(@{Name="U.S. Social Security Number (SSN)"; minCount="10"}, @{Name="Credit Card Number"; minCount="10"}) `
        -AccessScope NotInOrganization `
        -BlockAccess $true `
        -ReportSeverity High `
        -GenerateIncidentReport $true `
        -IncidentReportTarget $IncidentReportMailbox `
        -IncidentReportContent "Sender,Recipients,Subject,Bcc,Severity,Override,FalsePositive,DataClassification,MatchedItem" `
        -NotifyUser "Sender" `
        -NotifyPolicyTipDisplayOption "Always" `
        -NotifyPolicyTipCustomText "Your message/file contains a large amount of highly sensitive PII/Financial data and has been blocked. No overrides are permitted for this severity."
    Write-Log "Created High Severity Rule: $HighSeverityRuleName"
}

# Define Low/Medium Severity Rule (Block, but allow Override with Justification)
# Matches 1 to 9 instances
$LowSeverityRuleName = "$PiiPolicyName-LowSeverity-Override"
if (-not (Get-DlpComplianceRule -Identity $LowSeverityRuleName -ErrorAction SilentlyContinue)) {
    New-DlpComplianceRule -Name $LowSeverityRuleName `
        -Policy $PiiPolicyName `
        -ContentContainsSensitiveInformation @(@{Name="U.S. Social Security Number (SSN)"; minCount="1"; maxCount="9"}, @{Name="Credit Card Number"; minCount="1"; maxCount="9"}) `
        -AccessScope NotInOrganization `
        -BlockAccess $true `
        -ExceptIfHasSenderOverride $true `
        -ReportSeverity Medium `
        -GenerateIncidentReport $true `
        -IncidentReportTarget $IncidentReportMailbox `
        -IncidentReportContent "Sender,Recipients,Subject,Bcc,Severity,Override,FalsePositive,DataClassification,MatchedItem" `
        -NotifyUser "Sender" `
        -NotifyPolicyTipDisplayOption "Always" `
        -NotifyAllowOverride "WithJustification" `
        -NotifyPolicyTipCustomText "Your message/file contains sensitive PII/Financial data. It is blocked, but you may override with a valid business justification."
    Write-Log "Created Low/Medium Severity Rule: $LowSeverityRuleName"
}

# ----------------------------------------------------------------------------------------------
# 2. Health Data (HIPAA) Policy
# ----------------------------------------------------------------------------------------------
Write-Log "Creating Health Data (HIPAA) DLP Policy..."
$HipaaPolicyName = "Enterprise-DLP-Health-HIPAA"
$HipaaPolicyDescription = "Enterprise DLP policy for Health Data (HIPAA)."

if (-not (Get-DlpCompliancePolicy -Identity $HipaaPolicyName -ErrorAction SilentlyContinue)) {
    New-DlpCompliancePolicy -Name $HipaaPolicyName -Comment $HipaaPolicyDescription -ExchangeLocation All -SharePointLocation All -OneDriveLocation All -EndpointLocation All
    Write-Log "Created DLP Compliance Policy: $HipaaPolicyName"
}

# High Severity Rule (Strict Block)
$HipaaHighRuleName = "$HipaaPolicyName-HighSeverity-Block"
if (-not (Get-DlpComplianceRule -Identity $HipaaHighRuleName -ErrorAction SilentlyContinue)) {
    New-DlpComplianceRule -Name $HipaaHighRuleName `
        -Policy $HipaaPolicyName `
        -ContentContainsSensitiveInformation @(@{Name="U.S. Health Insurance Access Number"; minCount="5"}, @{Name="International Classification of Diseases (ICD-10-CM)"; minCount="5"}) `
        -AccessScope NotInOrganization `
        -BlockAccess $true `
        -ReportSeverity High `
        -GenerateIncidentReport $true `
        -IncidentReportTarget $IncidentReportMailbox `
        -IncidentReportContent "Sender,Recipients,Subject,Bcc,Severity,Override,FalsePositive,DataClassification,MatchedItem" `
        -NotifyUser "Sender" `
        -NotifyPolicyTipDisplayOption "Always" `
        -NotifyPolicyTipCustomText "Transmission of extensive health information is strictly blocked by company policy."
    Write-Log "Created High Severity Rule: $HipaaHighRuleName"
}

# Low Severity Rule (Override allowed)
$HipaaLowRuleName = "$HipaaPolicyName-LowSeverity-Override"
if (-not (Get-DlpComplianceRule -Identity $HipaaLowRuleName -ErrorAction SilentlyContinue)) {
    New-DlpComplianceRule -Name $HipaaLowRuleName `
        -Policy $HipaaPolicyName `
        -ContentContainsSensitiveInformation @(@{Name="U.S. Health Insurance Access Number"; minCount="1"; maxCount="4"}, @{Name="International Classification of Diseases (ICD-10-CM)"; minCount="1"; maxCount="4"}) `
        -AccessScope NotInOrganization `
        -BlockAccess $true `
        -ExceptIfHasSenderOverride $true `
        -ReportSeverity Medium `
        -GenerateIncidentReport $true `
        -IncidentReportTarget $IncidentReportMailbox `
        -IncidentReportContent "Sender,Recipients,Subject,Bcc,Severity,Override,FalsePositive,DataClassification,MatchedItem" `
        -NotifyUser "Sender" `
        -NotifyPolicyTipDisplayOption "Always" `
        -NotifyAllowOverride "WithJustification" `
        -NotifyPolicyTipCustomText "Sensitive health data detected. You must provide a business justification to proceed."
    Write-Log "Created Low/Medium Severity Rule: $HipaaLowRuleName"
}

# ----------------------------------------------------------------------------------------------
# 3. GDPR Data Policy
# ----------------------------------------------------------------------------------------------
Write-Log "Creating GDPR Data DLP Policy..."
$GdprPolicyName = "Enterprise-DLP-GDPR"
$GdprPolicyDescription = "Enterprise DLP policy for EU GDPR compliance."

if (-not (Get-DlpCompliancePolicy -Identity $GdprPolicyName -ErrorAction SilentlyContinue)) {
    New-DlpCompliancePolicy -Name $GdprPolicyName -Comment $GdprPolicyDescription -ExchangeLocation All -SharePointLocation All -OneDriveLocation All -EndpointLocation All
    Write-Log "Created DLP Compliance Policy: $GdprPolicyName"
}

# General Block Rule
$GdprRuleName = "$GdprPolicyName-Block"
if (-not (Get-DlpComplianceRule -Identity $GdprRuleName -ErrorAction SilentlyContinue)) {
    New-DlpComplianceRule -Name $GdprRuleName `
        -Policy $GdprPolicyName `
        -ContentContainsSensitiveInformation @(@{Name="EU Debit Card Number"; minCount="1"}, @{Name="EU National Identification Number"; minCount="1"}) `
        -AccessScope NotInOrganization `
        -BlockAccess $true `
        -ExceptIfHasSenderOverride $true `
        -ReportSeverity High `
        -GenerateIncidentReport $true `
        -IncidentReportTarget $IncidentReportMailbox `
        -IncidentReportContent "Sender,Recipients,Subject,Bcc,Severity,Override,FalsePositive,DataClassification,MatchedItem" `
        -NotifyUser "Sender" `
        -NotifyPolicyTipDisplayOption "Always" `
        -NotifyAllowOverride "WithJustification" `
        -NotifyPolicyTipCustomText "EU GDPR sensitive data detected. You must provide a business justification to proceed. The incident will be audited."
    Write-Log "Created GDPR Severity Rule: $GdprRuleName"
}

Write-Log "DLP Implementation Deployment Complete."
Write-Log "Note: It can take up to 24 hours for DLP policies to fully propagate across Exchange, SharePoint, OneDrive, and Endpoints."

# Disconnect Session
Disconnect-ExchangeOnline -Confirm:$false
Write-Log "Disconnected from Security & Compliance Center."
