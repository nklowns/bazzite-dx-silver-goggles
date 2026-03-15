#!/bin/bash
set -ouex pipefail

# Dell G15 (5521) Specific Tweaks
# Laptop: i7-12700H, RTX 3060

echo "Applying Dell G15 specific tweaks..."

# Install Dell management utilities
# Note: acpi_call is already provided by the Bazzite kernel (in-tree)
# Install our custom AWCC RPM compiled in the builder stage via transient mount
dnf5 install -y /tmp/builder_artifacts/awcc-*.rpm

# Enable AWCC Daemon (Installed natively via RPM)
systemctl enable awccd.service

# Mask thermald to prevent conflict with AWCC (critical for Dell G15)
systemctl mask thermald.service

# Make our utility scripts executable
chmod +x /usr/bin/g15-status

echo "Dell G15 tweaks applied (AWCC installed + status utility)."
