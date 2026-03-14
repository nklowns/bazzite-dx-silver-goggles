#!/bin/bash

set -ouex pipefail

CONTEXT_PATH="/ctx"
BUILD_SCRIPTS_PATH="${CONTEXT_PATH}/build_files"

echo "=== Starting Vespera Build ==="

# Run all numbered scripts in order
for script in ${BUILD_SCRIPTS_PATH}/*-*.sh; do
    if [[ -f "$script" ]]; then
        echo "=== Running $(basename $script) ==="
        bash "$script"
    fi
done

# Clean up DNF metadata and temporary files to satisfy bootc lint
# We only clean what we created and isn't a mount point
dnf5 clean all
rm -rf /var/tmp/* /var/lib/dnf/*

# Relocate AWCC database path (Risk 3 Mitigation)
# Ensure /var/lib/awcc exists for persistence (also handled by tmpfiles.d)
mkdir -p /var/lib/awcc
chmod 755 /var/lib/awcc

# If the database exists in /etc (from RPM), move it to /var/lib and symlink it
# This allows the data to persist across OCI updates in /var
if [ -f /etc/awcc/database.json ]; then
    echo "Relocating AWCC database to /var/lib/awcc for persistence..."
    mv /etc/awcc/database.json /var/lib/awcc/database.json
    ln -sf /var/lib/awcc/database.json /etc/awcc/database.json
fi

# Fix for bootc lint: missing sysusers for docker group
# uBlue images often have a docker group in /etc/group but no corresponding sysusers.d entry
if grep -q "^docker:" /etc/group && [ ! -f /usr/lib/sysusers.d/docker.conf ]; then
    echo "g docker - -" > /usr/lib/sysusers.d/docker.conf
fi

echo "=== Build Complete ==="