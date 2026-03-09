#!/bin/bash
set -ouex pipefail

# Dell G15 (5521) Specific Tweaks
# Laptop: i7-12700H, RTX 3060

echo "Applying Dell G15 specific tweaks..."

# Install Dell management utilities
dnf5 install -y \
    smbios-utils-python \
    akmod-acpi_call

# Install our custom AWCC RPM compiled in the builder stage
dnf5 install -y /tmp/awcc-1.16.9-*.rpm
rm -f /tmp/awcc-1.16.9-*.rpm

# Enable AWCC Daemon (Installed natively via RPM)
systemctl enable awccd.service

echo "Dell G15 tweaks applied (smbios-utils + AWCC installed)."
