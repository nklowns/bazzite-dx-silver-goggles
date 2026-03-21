#!/bin/bash

set -ouex pipefail

CONTEXT_PATH="/ctx"
BUILD_SCRIPTS_PATH="${CONTEXT_PATH}/build_files"


echo "::group:: === Copying System Files ==="
# Use rsync to align with Reference Patterns (Bluefin/Aurora)
# -r (recursive), -v (verbose), -K (keep symlinks), -l (links as links)
rsync -rvKl ${CONTEXT_PATH}/system_files/. /
echo "::endgroup::"

# Run all numbered scripts in order
for script in "${BUILD_SCRIPTS_PATH}"/*-*.sh; do
    if [[ -f "$script" ]]; then
        echo "::group:: === Running $(basename "$script") ==="
        bash "$script"
        echo "::endgroup::"
    fi
done

# Re-apply system_files to ensure our custom configs (like database.json)
# take priority over default files installed by RPMs in the previous step.
# This is critical for the final "Silver Goggles" layer.
echo "::group:: === Re-applying Priority Overrides ==="
rsync -rvKl ${CONTEXT_PATH}/system_files/. /
echo "::endgroup::"

# Apply systemd presets to ensure services (like awccd) are enabled
# and others (like thermald) are masked correctly.
systemctl preset-all

echo "::group:: === Cleanup ==="
# Clean up DNF metadata and temporary files to satisfy bootc lint
dnf5 clean all
rm -rf /var/tmp/* /var/lib/dnf/*

# Note: /var/lib/awcc is managed via /usr/lib/tmpfiles.d/awcc.conf
# following uBlue/BlueBuild state management patterns.

# Fix for bootc lint: missing sysusers for docker group
if grep -q "^docker:" /etc/group && [ ! -f /usr/lib/sysusers.d/docker.conf ]; then
    echo "g docker - -" > /usr/lib/sysusers.d/docker.conf
fi
echo "::endgroup::"

echo "=== Build Complete ==="