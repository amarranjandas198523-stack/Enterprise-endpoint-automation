#!/usr/bin/env python3
"""
macOS Atomic Testing Simulation

This script safely simulates adversary techniques (like creating an unauthorized
LaunchDaemon) on macOS to test Endpoint Security Framework (ESF) configurations
and visibility. It is entirely benign and reversible.
"""

import os
import sys
import subprocess
import time
import platform

PLIST_TEMPLATE = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.atomicredteam.benigntest</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/echo</string>
        <string>Benign Atomic Test LaunchDaemon</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
"""

def simulate_launchdaemon():
    print("[*] Simulating Persistence Technique: Creating Benign LaunchDaemon...")
    daemon_path = "/Library/LaunchDaemons/com.atomicredteam.benigntest.plist"

    # Check if we have root privileges, required for /Library/LaunchDaemons
    if os.geteuid() != 0:
        print("[!] Root privileges required to write to /Library/LaunchDaemons. Try running with sudo.")
        sys.exit(1)

    try:
        # Create the benign plist file
        with open(daemon_path, 'w') as f:
            f.write(PLIST_TEMPLATE)
        print(f"[+] Successfully created benign LaunchDaemon: {daemon_path}")

        # Set permissions (typically required for LaunchDaemons)
        os.chmod(daemon_path, 0o644)
        print(f"[+] Set permissions 644 on {daemon_path}")

        # Load the daemon using launchctl
        subprocess.run(['launchctl', 'load', daemon_path], check=True)
        print(f"[+] Loaded LaunchDaemon via launchctl.")

        # Sleep briefly to ensure EDR/SIEM (ESF) registers the event
        time.sleep(5)

        # Clean up
        print("\n[*] Cleaning up benign LaunchDaemon...")
        subprocess.run(['launchctl', 'unload', daemon_path], check=True)
        os.remove(daemon_path)
        print("[+] Unloaded and deleted LaunchDaemon successfully.")

    except PermissionError:
        print(f"[-] Permission denied when trying to write to {daemon_path}")
    except subprocess.CalledProcessError as e:
        print(f"[-] launchctl command failed: {e}")
    except Exception as e:
        print(f"[-] An error occurred: {e}")

def main():
    if platform.system() != 'Darwin':
        print("This script must be run on macOS (Darwin). Current platform:", platform.system())
        sys.exit(1)

    print("Starting Atomic Test Simulation on macOS...\n")
    simulate_launchdaemon()
    print("\nSimulation complete. Check your EDR/SIEM dashboards.")

if __name__ == "__main__":
    main()
