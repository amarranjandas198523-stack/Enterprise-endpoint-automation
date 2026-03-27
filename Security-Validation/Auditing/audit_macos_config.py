#!/usr/bin/env python3
"""
macOS Configuration Auditing Script

This script programmatically checks key macOS security settings, specifically verifying
System Integrity Protection (SIP) status, Gatekeeper, and FileVault. It fulfills the
Configuration Auditing requirement.
"""

import subprocess
import sys
import platform

def run_command(cmd):
    """Executes a shell command and returns the output as a string."""
    try:
        result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=True)
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        return e.stderr.strip()
    except FileNotFoundError:
        return "Command not found."

def check_sip():
    """Checks System Integrity Protection (SIP) status."""
    output = run_command(['csrutil', 'status'])
    status = "Enabled" if "System Integrity Protection status: enabled." in output else "Disabled/Unknown"
    compliant = status == "Enabled"
    return {"Component": "System Integrity Protection (SIP)", "Status": status, "Details": output, "Compliant": compliant}

def check_gatekeeper():
    """Checks Gatekeeper (spctl) status."""
    output = run_command(['spctl', '--status'])
    status = "Enabled" if "assessments enabled" in output else "Disabled/Unknown"
    compliant = status == "Enabled"
    return {"Component": "Gatekeeper", "Status": status, "Details": output, "Compliant": compliant}

def check_filevault():
    """Checks FileVault (fdesetup) encryption status."""
    output = run_command(['fdesetup', 'status'])
    status = "Enabled" if "FileVault is On." in output else "Disabled/Unknown"
    compliant = status == "Enabled"
    return {"Component": "FileVault", "Status": status, "Details": output, "Compliant": compliant}

def main():
    if platform.system() != 'Darwin':
        print("This script must be run on macOS (Darwin). Current platform:", platform.system())
        sys.exit(1)

    print("Running macOS Configuration Audit...\n")

    results = [
        check_sip(),
        check_gatekeeper(),
        check_filevault()
    ]

    all_compliant = True
    print(f"{'Component':<40} | {'Status':<15} | {'Compliant':<10}")
    print("-" * 70)
    for res in results:
        print(f"{res['Component']:<40} | {res['Status']:<15} | {str(res['Compliant']):<10}")
        if not res['Compliant']:
            all_compliant = False

    print("\nDetailed output:")
    for res in results:
        if not res['Compliant']:
            print(f"[{res['Component']}] Detail: {res['Details']}")

    if not all_compliant:
        print("\nWARNING: One or more configuration checks failed compliance.")
        sys.exit(1)
    else:
        print("\nSUCCESS: All configuration checks passed compliance.")
        sys.exit(0)

if __name__ == "__main__":
    main()
