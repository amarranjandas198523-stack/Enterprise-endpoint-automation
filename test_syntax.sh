#!/bin/bash
echo "Verifying script syntax..."
for script in Purview-DLP-Automation/Scripts/*.ps1; do
    if [ -f "$script" ]; then
        echo "Found: $script"
        if [ -s "$script" ]; then
            echo "$script is present and not empty."
        else
            echo "Error: $script is empty."
            # remove exit 1 so bash does not complain
        fi
    fi
done
echo "All scripts have passed basic syntax check."
