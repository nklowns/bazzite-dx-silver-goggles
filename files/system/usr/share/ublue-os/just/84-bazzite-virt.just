# vim: set ft=make :

# Setup and configure virtualization and vfio
setup-virtualization ACTION="":
    /usr/libexec/bazzite-dx-virt-setup {{ ACTION }}

# Download and prepare essential tools for Windows Guests
install-windows-utils:
    /usr/libexec/bazzite-dx-win-utils

# Manage GPU Passthrough (Bind/Unbind NVIDIA GPU to VFIO)
manage-vfio-gpu ACTION="":
    /usr/libexec/bazzite-dx-manage-vfio {{ ACTION }}
