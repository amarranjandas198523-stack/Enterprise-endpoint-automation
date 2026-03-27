<#
.SYNOPSIS
    Windows Hardening Script

.DESCRIPTION
    This PowerShell script provides automated system hardening, reinforcing
    Defensive PowerShell capabilities. It focuses on enabling key security
    features like Windows Defender, Windows Firewall across all profiles,
    and enforcing basic registry-based security policies.

.EXAMPLE
    .\Harden-Windows.ps1 -Force
#>

[CmdletBinding()]
param(
    [switch]$Force
)

function Enable-WindowsDefender {
    Write-Host "[*] Enabling and Configuring Windows Defender..." -ForegroundColor Cyan
    try {
        Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop
        Set-MpPreference -SubmitSamplesConsent 1 -ErrorAction Stop # 1: Send safe samples automatically
        Set-MpPreference -MAPSReporting 2 -ErrorAction Stop # 2: Advanced MAPS
        Write-Host "[+] Windows Defender Real-time Protection and MAPS enabled." -ForegroundColor Green
    } catch {
        Write-Error "Failed to configure Windows Defender: $_"
    }
}

function Enable-WindowsFirewall {
    Write-Host "[*] Enabling Windows Firewall for all profiles..." -ForegroundColor Cyan
    try {
        Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True -ErrorAction Stop
        Write-Host "[+] Windows Firewall enabled on all profiles." -ForegroundColor Green
    } catch {
        Write-Error "Failed to configure Windows Firewall: $_"
    }
}

function Enforce-BasicSecurityPolicies {
    Write-Host "[*] Enforcing basic registry-based security policies..." -ForegroundColor Cyan

    # Enable LSA Protection (Local Security Authority)
    $lsaKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
    if (!(Test-Path $lsaKey)) { New-Item -Path $lsaKey -Force | Out-Null }
    try {
        Set-ItemProperty -Path $lsaKey -Name "RunAsPPL" -Value 1 -Type DWord -Force -ErrorAction Stop
        Write-Host "[+] Enabled LSA Protection (RunAsPPL)." -ForegroundColor Green
    } catch {
        Write-Warning "Failed to enable LSA Protection: $_"
    }

    # Disable SMBv1
    $smb1Key = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters"
    if (!(Test-Path $smb1Key)) { New-Item -Path $smb1Key -Force | Out-Null }
    try {
        Set-ItemProperty -Path $smb1Key -Name "SMB1" -Value 0 -Type DWord -Force -ErrorAction Stop
        Write-Host "[+] Disabled SMBv1 Server." -ForegroundColor Green
    } catch {
        Write-Warning "Failed to disable SMBv1: $_"
    }
}

# --- Execution ---

Write-Host "Starting Windows Hardening Process..." -ForegroundColor Yellow

if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "This script requires Administrator privileges to apply hardening changes."
    if (!$Force) {
        Write-Host "Run with -Force to bypass this check (not recommended for production)."
        exit 1
    } else {
        Write-Host "Running in forced mode without verified admin privileges. Errors may occur." -ForegroundColor Red
    }
}

Enable-WindowsDefender
Enable-WindowsFirewall
Enforce-BasicSecurityPolicies

Write-Host "Windows Hardening Process Complete." -ForegroundColor Yellow
