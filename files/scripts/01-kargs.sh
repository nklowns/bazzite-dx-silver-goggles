#!/bin/bash
# scripts/01-kargs.sh
# Configures kernel arguments for Dell G15 5520 via bootc-native kargs.d.
# These arguments are applied on: bootc install / bootc upgrade / rpm-ostree rebase.
#
# Args summary:
#   vconsole.keymap=br          → Brazilian keyboard layout in TTY
#   bluetooth.disable_ertm=1    → Fixes Bluetooth stability issues
#   kvm.ignore_msrs=1           → Required for Windows VM passthrough
#   kvm.report_ignored_msrs=0   → Suppress noisy MSR logs
#   intel_iommu=on              → Enable IOMMU for VFIO GPU passthrough
#   iommu=pt                    → Passthrough mode (better performance + compat)
#   rd.driver.pre=vfio-pci      → Load vfio-pci before GPU drivers in initrd
#   vfio_pci.disable_vga=1      → Required for dGPU (RTX 3060) passthrough
set -ouex pipefail

KARGS_DIR="/usr/lib/bootc/kargs.d"
mkdir -p "${KARGS_DIR}"

cat >"${KARGS_DIR}/99-silver-goggles.toml" <<'TOML'
kargs = [
  "vconsole.keymap=br",
  "bluetooth.disable_ertm=1",
  "kvm.ignore_msrs=1",
  "kvm.report_ignored_msrs=0",
  "intel_iommu=on",
  "iommu=pt",
  "rd.driver.pre=vfio-pci",
  "vfio_pci.disable_vga=1"
]
TOML

echo "Kernel arguments written to ${KARGS_DIR}/99-silver-goggles.toml"
echo "They will be applied on next bootc install/upgrade/rebase."
