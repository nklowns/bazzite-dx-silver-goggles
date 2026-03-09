#!/bin/bash
set -ouex pipefail

# Dell G15 (5521) Specific Tweaks
# Laptop: i7-12700H, RTX 3060

echo "Applying Dell G15 specific tweaks..."

# Install Dell management utilities
dnf5 install -y \
    smbios-utils-python \
    akmod-acpi_call \
    cmake \
    ninja-build \
    meson \
    libx11-devel \
    libxkbcommon-devel \
    glfw-devel \
    libudev-devel \
    libglvnd-devel \
    gcc-c++ \
    wget

# Build AWCC from source (tr1xem/AWCC)
echo "Building AWCC from source..."
cd /tmp
git clone https://github.com/tr1xem/AWCC.git
cd AWCC
mkdir build && cd build
cmake -DCMAKE_INSTALL_PREFIX=/usr .. -G Ninja
ninja
ninja install

# Enable AWCC Daemon
systemctl enable awccd.service

echo "Dell G15 tweaks applied (smbios-utils + AWCC installed)."
