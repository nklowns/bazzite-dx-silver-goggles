#!/usr/bin/env bash
# Kernel arguments travel with the image through bootc's kargs.d, the same
# mechanism the BlueBuild kargs module used.
set -euo pipefail

readonly KARGS_DIR="/usr/lib/bootc/kargs.d"
mkdir -p "$KARGS_DIR"

cat >"${KARGS_DIR}/10-silver-goggles.toml" <<'EOF'
# Managed by bazzite-dx-silver-goggles. See AGENTS.md for why each argument exists.
kargs = [
  "vconsole.keymap=br",
  "kvm_intel.nested=1",
  "kvm.ignore_msrs=1",
  "kvm.report_ignored_msrs=0",
  "intel_iommu=on",
  # "iommu=pt" is deliberately absent: EAC Linux v2 requires IOMMU with
  # passthrough *disabled* (ujust check-anticheat), and strict mode still
  # supports VFIO. Add it per host with `rpm-ostree kargs --append=iommu=pt`
  # if the identity-map performance matters more than the readiness check.
  "nvidia-drm.modeset=1",
]
EOF

echo "Wrote $(wc -l <"${KARGS_DIR}/10-silver-goggles.toml") lines of kernel arguments"
