#!/bin/bash
set -ouex pipefail

# Enterprise pattern for kargs in bootc images (used by upstream)
# Writes kargs to a bootc configuration file.
mkdir -p /usr/lib/bootc/kargs.d/
cat << 'TOML' > /usr/lib/bootc/kargs.d/99-silver-goggles.toml
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

echo "KArgs configured to be applied on bootc install/rebase."
