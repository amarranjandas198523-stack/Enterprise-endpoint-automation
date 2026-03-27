<#
.SYNOPSIS
    Windows Configuration Auditing Script

.DESCRIPTION
    This script programmatically checks if key hardening settings are actively applied
    across Windows endpoints, fulfilling the Defensive PowerShell and Configuration
    Auditing requirements. It specifically checks Windows Defender status, Firewall rules,
    and BitLocker encryption status.

.EXAMPLE
    .\Audit-WindowsConfig.ps1
#>

[CmdletBinding()]
param()

$report = @()

# 1. Audit Windows Defender
Write-Verbose "Checking Windows Defender Status..."
try {
    $defenderStatus = Get-MpComputerStatus -ErrorAction Stop
    $report += [PSCustomObject]@{
        Component   = "Windows Defender"
        Status      = if ($defenderStatus.RealTimeProtectionEnabled) { "Enabled" } else { "Disabled" }
        Details     = "AMServiceEnabled: $($defenderStatus.AMServiceEnabled)"
        Compliant   = $defenderStatus.RealTimeProtectionEnabled -and $defenderStatus.AMServiceEnabled
    }
} catch {
    $report += [PSCustomObject]@{
        Component   = "Windows Defender"
        Status      = "Error"
        Details     = $_.Exception.Message
        Compliant   = $false
    }
}

# 2. Audit Windows Firewall
Write-Verbose "Checking Windows Firewall Status..."
try {
    $firewallProfiles = Get-NetFirewallProfile -ErrorAction Stop
    $allEnabled = $true
    $details = @()
    foreach ($profile in $firewallProfiles) {
        if ($profile.Enabled -ne 'True') {
            $allEnabled = $false
        }
        $details += "$($profile.Name): $($profile.Enabled)"
    }
    $report += [PSCustomObject]@{
        Component   = "Windows Firewall"
        Status      = if ($allEnabled) { "Enabled" } else { "Disabled/Partial" }
        Details     = $details -join ", "
        Compliant   = $allEnabled
    }
} catch {
    $report += [PSCustomObject]@{
        Component   = "Windows Firewall"
        Status      = "Error"
        Details     = $_.Exception.Message
        Compliant   = $false
    }
}

# 3. Audit BitLocker Status
Write-Verbose "Checking BitLocker Encryption Status..."
try {
    $bitlockerStatus = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
    $report += [PSCustomObject]@{
        Component   = "BitLocker ($($env:SystemDrive))"
        Status      = $bitlockerStatus.VolumeStatus
        Details     = "ProtectionStatus: $($bitlockerStatus.ProtectionStatus)"
        Compliant   = ($bitlockerStatus.VolumeStatus -eq 'FullyEncrypted') -and ($bitlockerStatus.ProtectionStatus -eq 'On')
    }
} catch {
    $report += [PSCustomObject]@{
        Component   = "BitLocker ($($env:SystemDrive))"
        Status      = "Error"
        Details     = $_.Exception.Message
        Compliant   = $false
    }
}

# Output the report
$report | Format-Table -AutoSize

# Exit with code 1 if non-compliant
if ($report.Compliant -contains $false) {
    Write-Warning "One or more configuration checks failed compliance."
    exit 1
} else {
    Write-Host "All configuration checks passed compliance." -ForegroundColor Green
    exit 0
}
