<#
.SYNOPSIS
    Windows Atomic Testing Simulation

.DESCRIPTION
    This PowerShell script safely simulates adversary techniques (like modifying a
    specific registry key for benign persistence) to validate EDR/SIEM alerts.
    It is designed to be completely non-destructive and highly visible for testing.

.EXAMPLE
    .\Atomic-Test-Windows.ps1 -TestType Persistence
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Persistence", "Discovery")]
    [string]$TestType = "Persistence"
)

function Simulate-Persistence {
    Write-Host "[*] Simulating Persistence Technique: Registry Run Key..." -ForegroundColor Cyan
    $runKeyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    $testName = "BenignAtomicTest"
    $testValue = "C:\Windows\System32\cmd.exe /c echo Benign Atomic Test"

    try {
        # Create the benign run key
        New-ItemProperty -Path $runKeyPath -Name $testName -Value $testValue -PropertyType String -Force | Out-Null
        Write-Host "[+] Successfully created benign run key: $testName at $runKeyPath" -ForegroundColor Green

        # Sleep briefly to ensure EDR/SIEM registers the event
        Start-Sleep -Seconds 5

        # Clean up
        Remove-ItemProperty -Path $runKeyPath -Name $testName -Force | Out-Null
        Write-Host "[+] Cleaned up benign run key." -ForegroundColor Green
    } catch {
        Write-Error "Failed to simulate persistence: $_"
    }
}

function Simulate-Discovery {
    Write-Host "[*] Simulating Discovery Technique: System Network Configuration Discovery..." -ForegroundColor Cyan
    try {
        # Execute common discovery commands typically used by attackers (and admins)
        Write-Host "Executing 'ipconfig /all'..."
        $ipconfigOutput = ipconfig /all

        Write-Host "Executing 'netstat -an'..."
        $netstatOutput = netstat -an

        Write-Host "Executing 'arp -a'..."
        $arpOutput = arp -a

        Write-Host "[+] Successfully executed discovery commands. Check SIEM/EDR for detection." -ForegroundColor Green
    } catch {
        Write-Error "Failed to simulate discovery: $_"
    }
}

Write-Host "Starting Atomic Test Simulation on Windows..." -ForegroundColor Yellow

switch ($TestType) {
    "Persistence" {
        Simulate-Persistence
    }
    "Discovery" {
        Simulate-Discovery
    }
}

Write-Host "Simulation complete." -ForegroundColor Yellow
