# vim: set ft=make :

# Setup and configure virtualization and vfio
setup-virtualization ACTION="":
    /usr/libexec/bazzite-dx-virt-setup {{ ACTION }}

# Download and prepare essential tools for Windows Guests
install-windows-utils:
    /usr/libexec/bazzite-dx-win-utils

# Download and prepare essential tools for macOS Guests (Ventura, Sonoma, Sequoia)
install-macos-utils:
    /usr/libexec/bazzite-dx-macos-utils

# Manage GPU Passthrough (Bind/Unbind NVIDIA GPU to VFIO)
manage-vfio-gpu ACTION="":
    /usr/libexec/bazzite-dx-manage-vfio {{ ACTION }}
