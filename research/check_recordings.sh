#!/bin/bash
# Run this on your Raspberry Pi to check what files were created

echo "=== Checking recordings directory ==="
if [ -d "recordings" ]; then
    echo "Found recordings directory"
    find recordings -type f -ls
    echo ""
    echo "=== File types ==="
    find recordings -type f -exec file {} \;
else
    echo "No recordings directory found"
fi
