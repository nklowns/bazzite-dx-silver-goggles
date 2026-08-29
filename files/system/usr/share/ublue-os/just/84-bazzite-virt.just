# vim: set ft=make :

# Setup and configure host virtualization readiness (IOMMU, KVM, CPU flags)
setup-virtualization ACTION="":
    /usr/libexec/bazzite-dx-virt-setup {{ ACTION }}

# Manage Windows Guest Virtual Machines & VirtIO tooling
windows-utils ACTION="":
    /usr/libexec/bazzite-dx-win-utils {{ ACTION }}

# Manage macOS Guest Virtual Machines & OpenCore/Libvirt integration
macos-utils ACTION="":
    /usr/libexec/bazzite-dx-macos-utils {{ ACTION }}

# Legacy compatibility aliases
install-windows-utils:
    /usr/libexec/bazzite-dx-win-utils

install-macos-utils:
    /usr/libexec/bazzite-dx-macos-utils

# Manage GPU Passthrough (Bind/Unbind NVIDIA GPU to VFIO)
manage-vfio-gpu ACTION="":
    /usr/libexec/bazzite-dx-manage-vfio {{ ACTION }}


