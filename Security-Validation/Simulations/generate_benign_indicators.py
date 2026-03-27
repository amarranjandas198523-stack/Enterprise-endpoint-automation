#!/usr/bin/env python3
"""
Generate Benign Indicators

This script generates industry-standard benign files (EICAR test file) and specific,
non-harmful network traffic patterns to reliably trigger anti-malware and network
intrusion detection systems.
"""

import os
import urllib.request
import urllib.error
import time
import socket

# Standard EICAR string
EICAR_STRING = r"X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*"

def generate_eicar_file():
    """Generates the benign EICAR test file to trigger anti-malware."""
    filename = "eicar_test.txt"
    filepath = os.path.join(os.getcwd(), filename)
    print(f"[*] Generating EICAR test file at {filepath}...")

    try:
        with open(filepath, 'w') as f:
            f.write(EICAR_STRING)
        print(f"[+] Successfully generated EICAR file. Expected EDR/Anti-malware alert.")

        # Give EDR time to scan and potentially quarantine/delete the file
        time.sleep(5)

        if os.path.exists(filepath):
            print(f"[-] EICAR file still exists. Your anti-malware may not be active or configured to quarantine.")
            # Optional cleanup
            os.remove(filepath)
            print("[+] Cleaned up EICAR file manually.")
        else:
            print("[+] EICAR file was automatically removed/quarantined by your security tools.")

    except PermissionError:
        print(f"[-] Permission denied when writing {filepath}.")
    except Exception as e:
        print(f"[-] Error writing EICAR file: {e}")

def generate_benign_network_traffic():
    """Generates benign network traffic to a known test domain."""
    # Using example.com as a universally benign domain for testing network logging
    test_domain = "example.com"
    print(f"\n[*] Generating benign network traffic to {test_domain}...")

    try:
        # Resolve DNS
        print(f"[1] Resolving DNS for {test_domain}...")
        ip_address = socket.gethostbyname(test_domain)
        print(f"    -> Resolved to {ip_address}")

        # Make a benign HTTP request
        print(f"[2] Making HTTP GET request to http://{test_domain}...")
        url = f"http://{test_domain}"
        req = urllib.request.Request(url, headers={'User-Agent': 'Security-Validation-Agent'})
        with urllib.request.urlopen(req, timeout=5) as response:
            status = response.getcode()
            print(f"    -> Received HTTP status code: {status}")

        print("[+] Network traffic simulation complete. Check SIEM/Network IDS for DNS and HTTP logs.")

    except socket.gaierror:
        print(f"[-] Failed to resolve {test_domain}.")
    except urllib.error.URLError as e:
        print(f"[-] HTTP request failed: {e.reason}")
    except Exception as e:
        print(f"[-] Network simulation error: {e}")

def main():
    print("=== Benign Indicator Generation ===")
    generate_eicar_file()
    generate_benign_network_traffic()
    print("===================================")

if __name__ == "__main__":
    main()
