#!/usr/bin/env python3
"""
Security Automation Script

This Python script is designed for analyzing security logs and automating incident
response tasks. In a production environment, this would integrate with SIEM APIs or
EDR platforms. For this implementation, it parses standard log files to identify
potential security events (like multiple failed logins or identified benign tests)
and aggregates the results.

Usage:
  python3 analyze_security_logs.py /path/to/log/directory/or/file
"""

import sys
import os
import re
from collections import defaultdict

# --- Configuration & Threat Indicators ---
# These regex patterns simulate identifying suspicious or interesting events in logs
PATTERNS = {
    "Failed Login": re.compile(r"failed (password|login)", re.IGNORECASE),
    "Benign EICAR Detected": re.compile(r"eicar[-_]test", re.IGNORECASE),
    "Atomic Test Triggered": re.compile(r"benign atomic test", re.IGNORECASE),
    "Privilege Escalation Attempt": re.compile(r"(sudo:.*incorrect password|authentication failure)", re.IGNORECASE)
}

def analyze_file(filepath):
    """Parses a single log file for interesting patterns."""
    results = defaultdict(int)
    suspicious_lines = []

    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            for line_num, line in enumerate(f, 1):
                for event_type, pattern in PATTERNS.items():
                    if pattern.search(line):
                        results[event_type] += 1
                        # Capture context for high severity (e.g., failed logins)
                        if event_type in ["Failed Login", "Privilege Escalation Attempt"]:
                            suspicious_lines.append(f"{os.path.basename(filepath)}:{line_num} -> {line.strip()}")
    except IOError as e:
        print(f"[-] Error reading {filepath}: {e}", file=sys.stderr)

    return results, suspicious_lines

def main(target_path):
    print(f"[*] Starting Security Log Analysis on: {target_path}")

    overall_results = defaultdict(int)
    all_suspicious_lines = []
    files_processed = 0

    if os.path.isfile(target_path):
        results, lines = analyze_file(target_path)
        for k, v in results.items(): overall_results[k] += v
        all_suspicious_lines.extend(lines)
        files_processed += 1
    elif os.path.isdir(target_path):
        for root, _, files in os.walk(target_path):
            for file in files:
                filepath = os.path.join(root, file)
                # Only analyze files that look like text logs to avoid binary files
                if file.endswith(('.log', '.txt', '.csv')) or 'log' in file.lower():
                    results, lines = analyze_file(filepath)
                    for k, v in results.items(): overall_results[k] += v
                    all_suspicious_lines.extend(lines)
                    files_processed += 1
    else:
        print(f"[-] Target path {target_path} is neither a file nor a directory.", file=sys.stderr)
        sys.exit(1)

    # --- Output Report ---
    print(f"\n[+] Analysis Complete. Processed {files_processed} log file(s).\n")
    print("=== Summary of Identified Security Events ===")

    if not overall_results:
        print("  No significant security events identified.")
    else:
        for event_type, count in overall_results.items():
            print(f"  {event_type}: {count} instance(s)")

    if all_suspicious_lines:
        print("\n=== Critical Context (Sample Logs) ===")
        # Limit output to prevent massive terminal flooding
        for line in all_suspicious_lines[:20]:
            print(f"  {line}")
        if len(all_suspicious_lines) > 20:
             print(f"  ... and {len(all_suspicious_lines) - 20} more critical logs truncated.")

    print("===========================================")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 analyze_security_logs.py <file_or_directory_path>")
        sys.exit(1)

    target = sys.argv[1]
    main(target)
