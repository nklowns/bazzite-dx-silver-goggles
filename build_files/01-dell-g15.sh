#!/bin/bash
set -ouex pipefail

# Dell G15 (5521) Specific Tweaks
# Laptop: i7-12700H, RTX 3060

echo "Applying Dell G15 specific tweaks..."

# Install Dell management utilities
# Note: acpi_call is already provided by the Bazzite kernel (in-tree)
dnf5 install -y --skip-unavailable \
    smbios-utils-python

# Install our custom AWCC RPM compiled in the builder stage via transient mount
dnf5 install -y /tmp/builder_artifacts/awcc-1.16.9-*.rpm

# Enable AWCC Daemon (Installed natively via RPM)
systemctl enable awccd.service

# Mask thermald to prevent conflict with AWCC (critical for Dell G15)
systemctl mask thermald.service

echo "Dell G15 tweaks applied (smbios-utils + AWCC installed)."
